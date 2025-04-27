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
    // Inject CommandRunnerViewModel
    private let commandRunnerViewModel: CommandRunnerViewModel

    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isSendingMessage: Bool = false // Track sending state
    @Published var isThinking: Bool = false
    // Persist interactionMode using AppStorage
    @AppStorage("interactionMode") var interactionMode: InteractionMode = .ask // Default to .ask if not set
    // Trigger for auto-scrolling chat on content updates
    @Published var scrollTrigger: UUID = UUID()

    // Computed property for Agent Mode Toggle binding
    var isAgentModeBinding: Binding<Bool> {
        Binding(
            get: { self.interactionMode == .agent },
            set: { self.interactionMode = $0 ? .agent : .ask }
        )
    }

    // --- LM Studio Connection State ---
    @Published var serverURL: String = "http://localhost:1234" // Default, can be configured later
    @Published var availableModels: [ModelInfo] = []
    @Published var selectedModelId: String? = nil
    @Published var isLoadingModels: Bool = false
    @Published var connectionError: String? = nil
    // ---------------------------------

    private var apiTask: Task<Void, Never>? = nil // To manage the streaming task
    private let actionHandler: ActionHandler // <<< ADD ActionHandler instance

    init(folderViewModel: FolderViewModel, commandRunnerViewModel: CommandRunnerViewModel) { 
        self.folderViewModel = folderViewModel 
        self.commandRunnerViewModel = commandRunnerViewModel
        // Create the ActionHandler instance, passing dependencies <<< ADD Initialization
        self.actionHandler = ActionHandler(folderViewModel: folderViewModel, commandRunnerViewModel: commandRunnerViewModel)
        
        // Fetch models asynchronously on initialization
        Task {
            await fetchModels()
        }
        
        // Register the callback <<< ADD Callback Registration
        // Use weak self to avoid retain cycles if ActionHandler held a strong ref back
        actionHandler.registerSendResultCallback { [weak self] result, index in
            await self?.sendResultToLLM(actionResult: result, historyUpToMessageIndex: index)
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
            messages.removeLast()
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
                if line.hasPrefix("data:"), let data = line.dropFirst(6).data(using: .utf8) {
                    if data.isEmpty || data == Data("[DONE]".utf8) { continue }
                    
                    do {
                        let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
                        if let deltaContent = chunk.choices.first?.delta.content, !deltaContent.isEmpty {
                            print("DEBUG Token: \(deltaContent)") // <<< ADD THIS LINE
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
                            // Update scroll trigger whenever content changes
                            self.scrollTrigger = UUID() 
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
                    // Call the ActionHandler instead of the local method <<< UPDATE Call Site
                    await self.actionHandler.parseAndExecuteActions(responseContent: finalContent, originalMessageIndex: msgIndex)
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

    private func sendResultToLLM(actionResult: String, historyUpToMessageIndex: Int) async {
        print("--- Sending Action Result Back to LLM ---")
        guard let modelId = selectedModelId else {
            print("Error: No model selected for sending action result.")
            // How to handle this error? Maybe append to messages?
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
            isSendingMessage = false // Reset if URL fails
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            connectionError = "Failed to encode action result request: \(error.localizedDescription)"
            isSendingMessage = false // Reset if encoding fails
            return
        }

        // Reuse the streaming request logic
        print("Calling performStreamingRequest for action result feedback...")
        let requestStartTime = Date() // Define start time for this request phase
        await performStreamingRequest(request: request, requestStartTime: requestStartTime)
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
 