import Foundation
import SwiftUI // Needed for ObservableObject and @Published

// MARK: - Data Structures for LM Studio API

/// Represents the overall structure of the response from `/v1/models`
struct ModelListResponse: Codable {
    let data: [ModelInfo]
}

/// Represents a single model entry in the list
struct ModelInfo: Codable, Identifiable { // Identifiable for ForEach
    let id: String
}

/// Represents the request body for `/v1/chat/completions`
struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage] // Use existing ChatMessage struct
    let stream: Bool = true // Always stream for this app
    // Add other parameters like temperature, max_tokens if needed later
}

/// Represents a chunk of data received in the SSE stream
struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let role: ChatMessage.Role? // Use ChatMessage.Role here
            let content: String? // The actual token
        }
        let delta: Delta
        let finish_reason: String? // Indicates end of stream
    }
    let id: String // Chunk ID
    let object: String // Type of object (e.g., "chat.completion.chunk")
    let created: Int // Timestamp
    let model: String // Model used
    let choices: [Choice]
}

// Define Interaction Mode
// Make enum RawRepresentable with String raw values for AppStorage
enum InteractionMode: String {
    case ask
    case agent
}

// MARK: - ViewModel

/// Manages the state and logic for the chat view.
@MainActor // Ensure UI updates happen on the main thread
class ChatViewModel: ObservableObject {

    // Inject FolderViewModel
    private let folderViewModel: FolderViewModel

    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isSendingMessage: Bool = false // Track sending state
    @Published var isThinking: Bool = false
    // Persist interactionMode using AppStorage
    @AppStorage("interactionMode") var interactionMode: InteractionMode = .ask // Default to .ask if not set

    // --- LM Studio Connection State ---
    @Published var serverURL: String = "http://localhost:1234" // Default, can be configured later
    @Published var availableModels: [ModelInfo] = []
    @Published var selectedModelId: String? = nil
    @Published var isLoadingModels: Bool = false
    @Published var connectionError: String? = nil
    // ---------------------------------

    private var apiTask: Task<Void, Never>? = nil // To manage the streaming task

    init(folderViewModel: FolderViewModel) { // Accept FolderViewModel
        self.folderViewModel = folderViewModel // Store it
        // Fetch models asynchronously on initialization
        Task {
            await fetchModels()
        }
    }

    // --- Network Fetching ---

    func fetchModels() async {
        isLoadingModels = true
        connectionError = nil
        availableModels = [] // Clear previous models

        // Construct the full URL
        guard let url = URL(string: serverURL + "/v1/models") else {
            connectionError = "Invalid server URL."
            isLoadingModels = false
            return
        }

        do {
            // Perform the network request
            let (data, response) = try await URLSession.shared.data(from: url)

            // Check HTTP status code
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                connectionError = "Failed to connect. Status code: \(statusCode)"
                isLoadingModels = false
                return
            }

            // Decode the JSON response
            let decodedResponse = try JSONDecoder().decode(ModelListResponse.self, from: data)
            availableModels = decodedResponse.data

            // Select the first model by default if available
            if let firstModel = availableModels.first {
                selectedModelId = firstModel.id
            }

        } catch let decodingError as DecodingError {
            connectionError = "Failed to decode models: \(decodingError.localizedDescription)"
            print("Decoding Error: \(decodingError)") // More detailed log for debugging
        } catch {
            connectionError = "Failed to fetch models: \(error.localizedDescription)"
        }

        isLoadingModels = false
    }

    // --- Chat Actions ---

    private func loadSystemPrompt() -> String {
        let filename = interactionMode == .agent ? "system_prompt_agent" : "system_prompt_ask"
        
        // Use Bundle.module to find resources within the package target
        // It automatically handles the correct location within the build products (like _Buddy.bundle)
        guard let fileURL = Bundle.module.url(forResource: filename, withExtension: "txt") else {
            print("Error: System prompt file \(filename).txt not found within Bundle.module.")
            // Fallback prompt if file loading fails
            return "You are a helpful AI assistant."
        }
        
        // Use the existing helper to load the content
        return loadString(from: fileURL)
    }

    // Helper to load string content and handle errors
    private func loadString(from url: URL) -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("Error loading system prompt from \(url): \(error)")
            // Fallback prompt on read error
            return "You are a helpful AI assistant."
        }
    }

    func sendMessage() {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let modelId = selectedModelId else {
            print("Error: No model selected.")
            // Consider setting an error state for the UI
            return
        }
        guard !isSendingMessage else {
            print("Already sending a message.")
            return
        }

        let requestStartTime = Date() // Record start time

        isSendingMessage = true
        connectionError = nil // Clear previous errors

        // Append user message immediately
        let userMessage = ChatMessage(role: .user, content: currentInput)
        messages.append(userMessage)
        let history = messages // Capture current history for the request
        currentInput = "" // Clear input field
        
        // --- Prepare message history including system prompt ---
        var messagesForAPI: [ChatMessage] = []
        let systemPrompt = loadSystemPrompt()
        messagesForAPI.append(ChatMessage(role: .system, content: systemPrompt))

        // Append conversation history (contains the actual user message)
        messagesForAPI.append(contentsOf: history)
        // -------------------------------------------------------

        // Prepare request using the messagesForAPI list
        let requestBody = ChatCompletionRequest(model: modelId, messages: messagesForAPI)
        guard let url = URL(string: serverURL + "/v1/chat/completions") else {
            connectionError = "Invalid chat completions URL."
            isSendingMessage = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Potentially add Accept: text/event-stream if server requires
        // request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            connectionError = "Failed to encode request: \(error.localizedDescription)"
            isSendingMessage = false
            // Remove the optimistic user message if encoding fails?
            // messages.removeLast()
            return
        }

        // Start the streaming task, passing the start time
        apiTask = Task {
            await performStreamingRequest(request: request, requestStartTime: requestStartTime)
        }
    }

    private func performStreamingRequest(request: URLRequest, requestStartTime: Date) async {
        var assistantResponseMessage = ChatMessage(role: .assistant, content: "")
        var messageIndex: Int? = nil
        var firstTokenTime: Date? = nil
        var tokenCount = 0
        
        defer {
            // Ensure sending state is reset even if task is cancelled
            isSendingMessage = false
            apiTask = nil
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                connectionError = "Chat request failed. Status code: \(statusCode)"
                return
            }

            // Process the stream line by line
            print("DEBUG: Starting stream processing for request starting at \(requestStartTime)") // Add timing info
            for try await line in bytes.lines {
                print("DEBUG: Received line: \(line)") // <<< Log the raw line
                if line.hasPrefix("data:"), let data = line.dropFirst(6).data(using: .utf8) {
                    if data.isEmpty || data == Data("[DONE]".utf8) { continue }
                    
                    do {
                        let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
                        if let deltaContent = chunk.choices.first?.delta.content, !deltaContent.isEmpty {
                             // Check if deltaContent is not empty before counting as a token
                            
                            // --- Stat Calculation --- 
                            if firstTokenTime == nil {
                                firstTokenTime = Date() // Record time of first token
                                // Calculate Time To First Token (TTFT)
                                let ttft = firstTokenTime!.timeIntervalSince(requestStartTime)
                                // Update message with TTFT
                                if messageIndex != nil {
                                     messages[messageIndex!].ttft = ttft
                                } else {
                                     assistantResponseMessage.ttft = ttft
                                }
                            }
                            // Assuming each non-empty chunk is approx. 1 token
                            tokenCount += 1 
                            // --- End Stat Calculation ---
                            
                            assistantResponseMessage.content += deltaContent
                            
                            // Add/update the message in the main array
                            if messageIndex == nil {
                                assistantResponseMessage.tokenCount = tokenCount // <<< Set initial token count
                                messages.append(assistantResponseMessage)
                                messageIndex = messages.count - 1
                            } else {
                                messages[messageIndex!].content = assistantResponseMessage.content
                                messages[messageIndex!].tokenCount = tokenCount // <<< Update token count
                            }
                        }
                        if chunk.choices.first?.finish_reason != nil {
                            break // End loop gracefully
                        }
                    } catch {
                        print("Failed to decode stream chunk: \(error), Line: \(line)")
                        connectionError = "Error decoding stream chunk: \(error.localizedDescription)"
                    }
                }
            }
            
            // --- Final Stats Calculation (after loop) ---
            if let index = messageIndex {
                let finishTime = Date()
                // Calculate duration from first token (or start) to finish
                let duration = finishTime.timeIntervalSince(firstTokenTime ?? requestStartTime)
                // Avoid division by zero, ensure tokenCount > 0
                if duration > 0.01 && tokenCount > 0 { 
                    // Calculate Tokens Per Second (TPS)
                    let tps = Double(tokenCount) / duration 
                    messages[index].tps = tps 
                } else {
                    // Set to nil if calculation is invalid/zero
                    messages[index].tps = nil 
                }
            }
            // ---------------------------------------------
            
            // --- Action Parsing (After Stream Ends) ---
            if interactionMode == .agent, let msgIndex = messageIndex, msgIndex < messages.count {
                let finalContent = messages[msgIndex].content
                // Don't await here, let it run concurrently
                Task { 
                    await parseAndExecuteActions(responseContent: finalContent, originalMessageIndex: msgIndex)
                }
            }
            // ------------------------------------------

        } catch {
            if !Task.isCancelled {
                 connectionError = "Network error during chat: \(error.localizedDescription)"
             }
        }
    }

    // --- Action Parsing & Execution --- 

    private func parseAndExecuteActions(responseContent: String, originalMessageIndex: Int) async {
        print("--- Parsing Actions (Agent Mode) ---")
        var actionFoundAndExecuted = false // Track if we need to send result
        var actionResultString = ""       // Store result if found

        let lines = responseContent.split(whereSeparator: \.isNewline)
        var i = 0
        while i < lines.count {
            let line = String(lines[i]) // Use full line string
            
            // Try parsing the line as an action
            if let parsedActionLine = line.parseAsAction() {
                
                var multiLineContent: String? = nil
                var finalParsedAction = parsedActionLine // Start with parsed line
                
                // Handle multi-line content specifically for EDIT_FILE
                if parsedActionLine.name == "EDIT_FILE" {
                    var contentLines: [String] = []
                    var foundStart = false
                    var j = i + 1
                    while j < lines.count {
                        let contentLine = String(lines[j])
                        if contentLine.trimmingCharacters(in: .whitespaces) == "CONTENT_START" {
                            foundStart = true
                        } else if contentLine.trimmingCharacters(in: .whitespaces) == "CONTENT_END" {
                            if foundStart {
                                multiLineContent = contentLines.joined(separator: "\n")
                                i = j // Advance main loop past the content block
                                break
                            }
                        } else if foundStart {
                            contentLines.append(contentLine)
                        }
                        j += 1
                    }
                    if multiLineContent == nil {
                        print("Warning: EDIT_FILE action found but CONTENT_START/CONTENT_END markers were missing or malformed.")
                        // Decide if we should still proceed or return an error? For now, proceed without content.
                    }
                    // Update the action object with the found content
                    finalParsedAction = ParsedAction(name: parsedActionLine.name, 
                                                   parameters: parsedActionLine.parameters, 
                                                   multiLineContent: multiLineContent)
                }

                // Print details
                print("Parsed Action: \(finalParsedAction.name), Params: \(finalParsedAction.parameters)")
                if let content = finalParsedAction.multiLineContent {
                    print("  Multi-line Content:")
                    print("---")
                    print("\(content)")
                    print("---")
                }
                
                // --- Execute the action --- 
                actionResultString = await execute(action: finalParsedAction) // Use potentially updated action
                actionFoundAndExecuted = true
                // --------------------------------
                break // Assume one action per response
            }
            i += 1
        }
        print("--- Finished Parsing. Action found: \(actionFoundAndExecuted) ---")

        // If an action was found and executed, send its result back
        if actionFoundAndExecuted {
            await sendResultToLLM(actionResult: actionResultString, historyUpToMessageIndex: originalMessageIndex)
        }
    }
    
    private func execute(action: ParsedAction) async -> String {
        print("Executing action '\(action.name)'...")
        
        // Ensure we have a working directory from FolderViewModel
        guard let workingDirectoryURL = folderViewModel.selectedFolderURL else {
            return formatErrorResult(action: action, message: "No folder selected in the sidebar.")
        }
        
        let fileManager = FileManager.default
        let resultString: String

        switch action.name {
        case "READ_FILE":
            guard let relativePath = action.parameters["path"], !relativePath.isEmpty else {
                return formatErrorResult(action: action, message: "Missing or empty 'path' parameter for READ_FILE.")
            }
            let fileURL = workingDirectoryURL.appendingPathComponent(relativePath)
            do {
                // Security check: Ensure file is within the working directory
                guard fileURL.path.starts(with: workingDirectoryURL.path) else {
                    return formatErrorResult(action: action, message: "Access denied: Path is outside the selected folder.")
                }
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                resultString = """
                ACTION_RESULT: READ_FILE(path='\(relativePath)')
                STATUS: SUCCESS
                CONTENT:
                \(content)
                """
            } catch {
                resultString = formatErrorResult(action: action, message: "Failed to read file: \(error.localizedDescription)")
            }

        case "LIST_DIR":
            let relativePath = action.parameters["path"] ?? "." // Default to current dir if no path
            let dirURL = workingDirectoryURL.appendingPathComponent(relativePath)
            do {
                // Security check
                guard dirURL.path.starts(with: workingDirectoryURL.path) else {
                    return formatErrorResult(action: action, message: "Access denied: Path is outside the selected folder.")
                }
                let items = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                var listing = ""
                for itemURL in items {
                    var itemName = itemURL.lastPathComponent
                    if let isDirectory = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory == true {
                        itemName += "/" // Append slash to directories
                    }
                    listing += itemName + "\n"
                }
                resultString = """
                ACTION_RESULT: LIST_DIR(path='\(relativePath)')
                STATUS: SUCCESS
                LISTING:
                \(listing.trimmingCharacters(in: .newlines))
                """
            } catch {
                resultString = formatErrorResult(action: action, message: "Failed to list directory: \(error.localizedDescription)")
            }

        case "EDIT_FILE":
            guard let relativePath = action.parameters["path"], !relativePath.isEmpty else {
                return formatErrorResult(action: action, message: "Missing or empty 'path' parameter for EDIT_FILE.")
            }
            guard let newContent = action.multiLineContent else {
                return formatErrorResult(action: action, message: "Missing content block (CONTENT_START/END) for EDIT_FILE.")
            }
            let fileURL = workingDirectoryURL.appendingPathComponent(relativePath)
            
            do {
                // Security check
                guard fileURL.path.starts(with: workingDirectoryURL.path) else {
                    return formatErrorResult(action: action, message: "Access denied: Path is outside the selected folder.")
                }
                
                // Write new content
                try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                // --- TODO: Implement Diff Generation (Deferred) --- 
                
                // Simplified Success Result String
                resultString = """
                ACTION_RESULT: EDIT_FILE(path='\(relativePath)')
                STATUS: SUCCESS
                """ // DIFF section removed
                
                // --- Signal FolderViewModel to select the edited file after refresh ---
                folderViewModel.urlToSelectAfterRefresh = fileURL
                // ---------------------------------------------------------------------

            } catch {
                 resultString = formatErrorResult(action: action, message: "Failed to write file: \(error.localizedDescription)")
            }

        default:
             resultString = formatErrorResult(action: action, message: "Unknown action name \'\(action.name)\'.")
        }

        print("Action Result:")
        print(resultString)
        return resultString
    }
    
    // Helper to format error results consistently
    private func formatErrorResult(action: ParsedAction, message: String) -> String {
        // Reconstruct original action string approximation for context
        let paramsString = action.parameters.map { "\($0.key)='\($0.value)'" }.joined(separator: ", ")
        let originalAction = "\(action.name)(\(paramsString))"
        return """
        ACTION_RESULT: \(originalAction)
        STATUS: ERROR: \(message)
        """
    }

    private func sendResultToLLM(actionResult: String, historyUpToMessageIndex: Int) async {
        print("--- Sending Action Result Back to LLM ---")
        guard let modelId = selectedModelId else {
            print("Error: No model selected for sending action result.")
            // How to handle this error? Maybe append to messages?
            return
        }
        
        // Prevent overlapping requests
        guard !isSendingMessage else {
            print("Already processing a message/action, cannot send result now.")
            // TODO: Queue this or handle concurrency better?
            return
        }
        isSendingMessage = true // Mark as busy
        connectionError = nil

        let resultWithInstruction = "Based on the following action result, please formulate a response for the user:\n\n\(actionResult)"

        // --- Prepare message history in chronological order ---
        var messagesForAPI: [ChatMessage] = []
        let systemPrompt = loadSystemPrompt() // Use current mode's prompt
        messagesForAPI.append(ChatMessage(role: .system, content: systemPrompt))
        
        // Append history UP TO and INCLUDING the message that requested the action
        if historyUpToMessageIndex >= 0 && historyUpToMessageIndex < messages.count {
             // Include the message that contained the ACTION request itself
            messagesForAPI.append(contentsOf: messages[...historyUpToMessageIndex]) 
        } else {
            print("Warning: Invalid history index (\(historyUpToMessageIndex)) for sending action result.")
            // Fallback: maybe send just the system prompt and the result? Or current full history?
            // Let's stick to the intended history for now.
        }

        // Append the action result message AFTER the history
        messagesForAPI.append(ChatMessage(role: .user, content: resultWithInstruction))
        // ------------------------------------------------------

        // Prepare request body
        let requestBody = ChatCompletionRequest(model: modelId, messages: messagesForAPI)
        guard let url = URL(string: serverURL + "/v1/chat/completions") else {
            connectionError = "Invalid chat completions URL."
            isSendingMessage = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            connectionError = "Failed to encode action result request: \(error.localizedDescription)"
            isSendingMessage = false
            return
        }

        // Reuse the streaming request logic (or create a non-streaming one if preferred)
        // Note: The result of *this* call will be processed by performStreamingRequest again,
        // which will update the UI with the LLM's response *after* processing the action result.
        print("Calling performStreamingRequest for action result feedback...")
        await performStreamingRequest(request: request, requestStartTime: Date())
        // isSendingMessage will be reset by performStreamingRequest's defer block
    }

    // Function to cancel the stream if needed (e.g., stop button)
    func cancelStreaming() {
        apiTask?.cancel()
        apiTask = nil
        isSendingMessage = false
        // Maybe handle partially received message state?
    }

    // Placeholder removed - functionality implemented
    func clearChat() {
        cancelStreaming() // Cancel any ongoing stream before clearing
        messages = []
    }
}
 