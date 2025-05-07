import Foundation
import SwiftUI // Needed for ObservableObject and @Published

// MARK: - Data Structures for LM Studio API

/// Represents the overall structure of the response from `/v1/models`
// ... existing code ...

/// Represents a single model entry in the list

/// Represents a chunk of data received in the SSE stream
// ... existing code ...

// Define Interaction Mode
// Make enum RawRepresentable with String raw values for AppStorage

// MARK: - ViewModel

// Step 2: Add LoadingState enum for local model loading
enum LoadingState: Equatable {
    case idle
    case loading(progress: Double?)
    case loaded(CombinedModelInfo)
    case error(String)
}

/// Manages the state and logic for the chat view.
@MainActor // Ensure UI updates happen on the main thread
class ChatViewModel: ObservableObject {

    // Inject FolderViewModel
    private let folderViewModel: FolderViewModel
    // Inject CommandRunnerViewModel
    private let commandRunnerViewModel: CommandRunnerViewModel

    // Add ChatService instance
    private let remoteChatService: RemoteChatService
    private let localChatService: LocalChatService

    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isSendingMessage: Bool = false // Track sending state
    @Published var isThinking: Bool = false
    // Persist interactionMode using AppStorage
    @AppStorage("interactionMode") var interactionMode: InteractionMode = .ask // Default to .ask if not set
    // Trigger for auto-scrolling chat on content updates
    @Published var scrollTrigger: UUID = UUID()
    @Published var isAwaitingFirstToken: Bool = false // <<< ADD STATE

    // Computed property for Agent Mode Toggle binding
    var isAgentModeBinding: Binding<Bool> {
        Binding(
            get: { self.interactionMode == .agent },
            set: { self.interactionMode = $0 ? .agent : .ask }
        )
    }

    // --- LM Studio Connection State ---
    @Published var serverURL: String = "http://localhost:1234" // Ollama default URL
    @Published var availableModels: [CombinedModelInfo] = [] // Use CombinedModelInfo
    @Published var selectedModelId: CombinedModelInfo.ID? = nil // Use CombinedModelInfo.ID
    @Published var isLoadingModels: Bool = false
    @Published var connectionError: String? = nil
    // Step 2: Local model loading state
    @Published var localModelLoadingState: LoadingState = .idle
    // ---------------------------------

    private var chatStreamTask: Task<Void, Never>? = nil // To manage the service stream task

    // Add the ActionHandler instance
    private let actionHandler: ActionHandler

    init(folderViewModel: FolderViewModel, commandRunnerViewModel: CommandRunnerViewModel, remoteChatService: RemoteChatService, localChatService: LocalChatService) { 
        self.folderViewModel = folderViewModel 
        self.commandRunnerViewModel = commandRunnerViewModel
        self.remoteChatService = remoteChatService // Store the service
        self.localChatService = localChatService // Store the local service
        // Create the ActionHandler instance, passing dependencies
        self.actionHandler = ActionHandler(folderViewModel: folderViewModel, commandRunnerViewModel: commandRunnerViewModel)
        
        // Fetch models asynchronously on initialization
        Task {
            await fetchModels()
        }
        
        // Register the callback
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
        localModelLoadingState = .idle // Reset local model loading state

        async let remoteModelsResult: Result<[CombinedModelInfo], Error> = Task {
            do {
                let models = try await remoteChatService.fetchAvailableModels()
                return .success(models)
            } catch {
                return .failure(error)
            }
        }.value

        async let localModelsResult: Result<[CombinedModelInfo], Error> = Task {
            do {
                let models = try await localChatService.fetchAvailableModels()
                return .success(models)
            } catch {
                return .failure(error)
            }
        }.value

        let remoteResult = await remoteModelsResult
        let localResult = await localModelsResult

        var combined: [CombinedModelInfo] = []
        var remoteError: String? = nil
        var localError: String? = nil

        switch remoteResult {
        case .success(let models):
            combined.append(contentsOf: models)
        case .failure(let error):
            remoteError = "Remote: \(error.localizedDescription)"
        }

        switch localResult {
        case .success(let models):
            combined.append(contentsOf: models)
        case .failure(let error):
            localError = "Local: \(error.localizedDescription)"
        }

        availableModels = combined

        // Prefer remote model for default selection, else local
        if let firstRemote = combined.first(where: { $0.type == .remote }) {
            selectedModelId = firstRemote.id
        } else if let firstLocal = combined.first(where: { $0.type == .local }) {
            selectedModelId = firstLocal.id
        } else {
            selectedModelId = nil
        }

        // Combine errors if any
        if let remoteError = remoteError, let localError = localError {
            connectionError = remoteError + "\n" + localError
        } else if let remoteError = remoteError {
            connectionError = remoteError
        } else if let localError = localError {
            connectionError = localError
        } else {
            connectionError = nil
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
        // Find the selected CombinedModelInfo based on the ID
        guard let currentModelId = selectedModelId,
              let model = availableModels.first(where: { $0.id == currentModelId }) else {
            print("Error: No model selected or found.")
            connectionError = "No model selected or the selected model is invalid."
            return
        }

        // Step 5: Handle local and remote models
        if model.type == .local {
            // Local model: ensure loaded, then send message
            guard !isSendingMessage else {
                print("Already sending a message.")
                return
            }
            isSendingMessage = true
            isAwaitingFirstToken = true
            connectionError = nil
            Task {
                // Ensure the model is loaded
                await loadSelectedLocalModelIfNeeded()
                // Check if loading failed
                if case .error(let errMsg) = localModelLoadingState {
                    connectionError = "Local model load error: \(errMsg)"
                    isSendingMessage = false
                    isAwaitingFirstToken = false
                    return
                }
                // Append user message immediately
                let userMessage = ChatMessage(role: .user, content: currentInput)
                messages.append(userMessage)
                let historyForRequest = messages
                let interactionModeForRequest = interactionMode
                let systemPrompt = loadSystemPrompt()
                currentInput = ""
                // Cancel any previous stream task before starting a new one
                chatStreamTask?.cancel()
                chatStreamTask = Task {
                    var assistantResponseMessage = ChatMessage(role: .assistant, content: "")
                    var messageIndex: Int? = nil
                    do {
                        let stream = localChatService.sendMessage(
                            history: historyForRequest,
                            systemPrompt: systemPrompt,
                            model: model,
                            interactionMode: interactionModeForRequest
                        )
                        for try await update in stream {
                            if Task.isCancelled { break }
                            switch update {
                            case .contentDelta(let deltaContent):
                                if isAwaitingFirstToken { isAwaitingFirstToken = false }
                                assistantResponseMessage.content += deltaContent
                                if messageIndex == nil {
                                    messages.append(assistantResponseMessage)
                                    messageIndex = messages.count - 1
                                } else {
                                    messages[messageIndex!].content = assistantResponseMessage.content
                                }
                                scrollTrigger = UUID()
                            case .usage(let usageMetrics):
                                if let index = messageIndex {
                                    messages[index].promptTokenCount = usageMetrics.prompt_tokens
                                    messages[index].tokenCount = usageMetrics.completion_tokens
                                    messages[index].promptTime = usageMetrics.prompt_time
                                    messages[index].generationTime = usageMetrics.generation_time
                                }
                            case .firstTokenTime(let ttft):
                                assistantResponseMessage.ttft = ttft
                                if let index = messageIndex { messages[index].ttft = ttft }
                            case .finalMetrics(let tps, let tokenCount):
                                if let index = messageIndex {
                                    messages[index].tps = tps
                                    if messages[index].tokenCount == nil { messages[index].tokenCount = tokenCount }
                                }
                            case .error(let error):
                                print("Stream error: \(error)")
                                connectionError = "Stream error: \(error.localizedDescription)"
                            }
                        }
                        if Task.isCancelled {
                            print("Local chat stream task cancelled.")
                        } else {
                            print("Local chat stream finished.")
                            if interactionModeForRequest == .agent, let msgIndex = messageIndex, msgIndex < messages.count {
                                let finalContent = messages[msgIndex].content
                                Task {
                                    await self.actionHandler.parseAndExecuteActions(responseContent: finalContent, originalMessageIndex: msgIndex)
                                }
                            }
                        }
                    } catch {
                        if !(error is CancellationError) {
                            print("Error processing local chat stream: \(error)")
                            connectionError = "Chat error: \(error.localizedDescription)"
                        }
                    }
                    isSendingMessage = false
                    isAwaitingFirstToken = false
                    chatStreamTask = nil
                }
            }
            return
        }

        // Remote model (existing logic)
        guard model.type == .remote else {
            print("Error: Unknown model type.")
            connectionError = "Unknown model type."
            return
        }
        guard !isSendingMessage else {
            print("Already sending a message.")
            return
        }
        isSendingMessage = true
        isAwaitingFirstToken = true // Set awaiting flag before starting task
        connectionError = nil // Clear previous errors

        // Append user message immediately
        let userMessage = ChatMessage(role: .user, content: currentInput)
        messages.append(userMessage)
        let historyForRequest = messages // Capture current history *before* potential assistant response
        let interactionModeForRequest = interactionMode // Capture current mode
        let systemPrompt = loadSystemPrompt()
        currentInput = "" // Clear input field

        // Cancel any previous stream task before starting a new one
        chatStreamTask?.cancel()

        chatStreamTask = Task {
            var assistantResponseMessage = ChatMessage(role: .assistant, content: "")
            var messageIndex: Int? = nil // Index in the `messages` array

            do {
                let stream = remoteChatService.sendMessage(
                    history: historyForRequest,
                    systemPrompt: systemPrompt,
                    model: model, // Pass the selected CombinedModelInfo
                    interactionMode: interactionModeForRequest
                )

                for try await update in stream {
                    // Check for cancellation after each stream item
                    if Task.isCancelled { break }

                    switch update {
                    case .contentDelta(let deltaContent):
                        if isAwaitingFirstToken {
                            isAwaitingFirstToken = false // Reset on first token
                        }
                        assistantResponseMessage.content += deltaContent
                        if messageIndex == nil {
                            // First content delta, add the message
                            messages.append(assistantResponseMessage)
                            messageIndex = messages.count - 1
                        } else {
                            // Subsequent deltas, update existing message
                            messages[messageIndex!].content = assistantResponseMessage.content
                        }
                        // Update scroll trigger whenever content changes
                        scrollTrigger = UUID()

                    case .usage(let usageMetrics):
                        print("DEBUG: Received usage metrics: \(usageMetrics)")
                        if let index = messageIndex {
                            messages[index].promptTokenCount = usageMetrics.prompt_tokens
                            messages[index].tokenCount = usageMetrics.completion_tokens // Update final token count
                            messages[index].promptTime = usageMetrics.prompt_time
                            messages[index].generationTime = usageMetrics.generation_time
                        }

                    case .firstTokenTime(let ttft):
                        print("DEBUG: Received TTFT: \(ttft)")
                        assistantResponseMessage.ttft = ttft // Store temporarily
                        if let index = messageIndex {
                            messages[index].ttft = ttft // Update if message exists
                        }

                    case .finalMetrics(let tps, let tokenCount):
                        print("DEBUG: Received final metrics - TPS: \(tps ?? -1), Tokens: \(tokenCount)")
                        if let index = messageIndex {
                            messages[index].tps = tps
                            // Usage might arrive later, so tokenCount from usage is preferred if available
                            if messages[index].tokenCount == nil {
                                messages[index].tokenCount = tokenCount
                            }
                        }

                    case .error(let error):
                        print("Stream error: \(error)")
                        connectionError = "Stream error: \(error.localizedDescription)"
                        // Potentially break or handle differently
                    }
                } // End of stream loop

                // --- Stream finished successfully (or cancelled) ---
                if Task.isCancelled {
                    print("Chat stream task cancelled.")
                } else {
                    print("Chat stream finished.")
                    // --- Action Parsing (After Stream Ends) ---
                    if interactionModeForRequest == .agent, let msgIndex = messageIndex, msgIndex < messages.count {
                        let finalContent = messages[msgIndex].content
                        // Don't await here, let it run concurrently
                        Task {
                            await self.actionHandler.parseAndExecuteActions(responseContent: finalContent, originalMessageIndex: msgIndex)
                        }
                    }
                }

            } catch {
                // Handle errors thrown by the service call itself or stream setup
                if !(error is CancellationError) {
                    print("Error processing chat stream: \(error)")
                    connectionError = "Chat error: \(error.localizedDescription)"
                }
            }

            // --- Cleanup regardless of how the task ended ---
            isSendingMessage = false
            isAwaitingFirstToken = false
            chatStreamTask = nil
        }
    }

    // --- Action Parsing & Execution ---

    private func sendResultToLLM(actionResult: String, historyUpToMessageIndex: Int) async {
        print("--- Sending Action Result Back to LLM --- (Refactored for local/remote) ---")
        guard let currentModelId = selectedModelId,
              let model = availableModels.first(where: { $0.id == currentModelId }) else {
            print("Error: No model selected for sending action result.")
            return
        }

        isSendingMessage = true // Mark as busy
        isAwaitingFirstToken = true // Expecting a response
        connectionError = nil

        // --- Prepare message history in chronological order ---
        var messagesForAPI: [ChatMessage] = []
        let systemPrompt = loadSystemPrompt() // Use current mode's prompt
        messagesForAPI.append(ChatMessage(role: .system, content: systemPrompt))

        // Append history UP TO and INCLUDING the message that requested the action
        if historyUpToMessageIndex >= 0 && historyUpToMessageIndex < messages.count {
            messagesForAPI.append(contentsOf: messages[...historyUpToMessageIndex])
        } else {
            print("Warning: Invalid history index (\(historyUpToMessageIndex)) for sending action result.")
        }
        messagesForAPI.append(ChatMessage(role: .user, content: actionResult))
        messages.append(ChatMessage(role: .user, content: actionResult)) // Also append to main history
        // ---------------------------------

        // Cancel previous task
        chatStreamTask?.cancel()

        // --- Use Service ---
        let interactionModeForRequest = interactionMode // Capture current mode
        chatStreamTask = Task {
            var assistantResponseMessage = ChatMessage(role: .assistant, content: "")
            var messageIndex: Int? = nil
            do {
                let stream: AsyncThrowingStream<ChatStreamUpdate, Error>
                if model.type == .local {
                    stream = localChatService.sendMessage(
                        history: messagesForAPI,
                        systemPrompt: systemPrompt,
                        model: model,
                        interactionMode: interactionModeForRequest
                    )
                } else {
                    stream = remoteChatService.sendMessage(
                        history: messagesForAPI,
                        systemPrompt: systemPrompt,
                        model: model,
                        interactionMode: interactionModeForRequest
                    )
                }
                for try await update in stream {
                    if Task.isCancelled { break }
                    switch update {
                    case .contentDelta(let deltaContent):
                        if isAwaitingFirstToken { isAwaitingFirstToken = false }
                        assistantResponseMessage.content += deltaContent
                        if messageIndex == nil {
                            messages.append(assistantResponseMessage)
                            messageIndex = messages.count - 1
                        } else {
                            messages[messageIndex!].content = assistantResponseMessage.content
                        }
                        scrollTrigger = UUID()
                    case .usage(let usageMetrics):
                        if let index = messageIndex {
                            messages[index].promptTokenCount = usageMetrics.prompt_tokens
                            messages[index].tokenCount = usageMetrics.completion_tokens
                            messages[index].promptTime = usageMetrics.prompt_time
                            messages[index].generationTime = usageMetrics.generation_time
                        }
                    case .firstTokenTime(let ttft):
                        assistantResponseMessage.ttft = ttft
                        if let index = messageIndex { messages[index].ttft = ttft }
                    case .finalMetrics(let tps, let tokenCount):
                        if let index = messageIndex {
                            messages[index].tps = tps
                            if messages[index].tokenCount == nil { messages[index].tokenCount = tokenCount }
                        }
                    case .error(let error):
                        connectionError = "Stream error: \(error.localizedDescription)"
                    }
                }
                // No action parsing needed after action result response
            } catch {
                if !(error is CancellationError) {
                    connectionError = "Chat error after action: \(error.localizedDescription)"
                }
            }
            // Cleanup
            isSendingMessage = false
            isAwaitingFirstToken = false
            chatStreamTask = nil
        }
    }

    // Function to cancel the stream if needed (e.g., stop button)
    func cancelStreaming() {
        // Cancel the new stream task
        chatStreamTask?.cancel()
        chatStreamTask = nil
        // Reset state immediately
        isSendingMessage = false
        isAwaitingFirstToken = false
        // Step 6: Cancel the correct service's request
        if let currentModelId = selectedModelId,
           let model = availableModels.first(where: { $0.id == currentModelId }) {
            if model.type == .local {
                localChatService.cancelCurrentRequest()
            } else if model.type == .remote {
                remoteChatService.cancelCurrentRequest()
            }
        }
    }

    // Placeholder removed - functionality implemented
    func clearChat() {
        cancelStreaming() // Cancel any ongoing stream before clearing
        messages = []
    }

    // Step 4: Helper to check if the selected local model is loaded
    var isSelectedLocalModelLoaded: Bool {
        guard let selectedId = selectedModelId,
              let selected = availableModels.first(where: { $0.id == selectedId && $0.type == .local })
        else { return false }
        // Check if the localChatService has this model loaded (by id)
        // We'll need to expose a method or property on LocalChatService for this if not already present
        // For now, assume LocalChatService has a method: isModelLoaded(id: String) -> Bool
        // For now, always return false to avoid compile error.
        return localChatServiceIsModelLoaded(selected.id)
    }

    // Placeholder for LocalChatService model loaded check
    private func localChatServiceIsModelLoaded(_ id: String) -> Bool {
        // Compare the full unique ID (with 'local:' prefix)
        return localChatService.currentModelId == id
    }

    // Step 4: Method to load the selected local model if needed
    func loadSelectedLocalModelIfNeeded() async {
        guard let selectedId = selectedModelId,
              let selected = availableModels.first(where: { $0.id == selectedId && $0.type == .local })
        else { return }
        if !localChatServiceIsModelLoaded(selected.id) {
            localModelLoadingState = .loading(progress: nil)
            do {
                try await localChatService.loadLocalModel(selected)
                localModelLoadingState = .loaded(selected)
            } catch {
                localModelLoadingState = .error(error.localizedDescription)
            }
        }
    }
}
 
