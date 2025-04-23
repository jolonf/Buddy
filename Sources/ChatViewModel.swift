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

// MARK: - ViewModel

/// Manages the state and logic for the chat view.
@MainActor // Ensure UI updates happen on the main thread
class ChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isSendingMessage: Bool = false // Track sending state

    // --- LM Studio Connection State ---
    @Published var serverURL: String = "http://localhost:1234" // Default, can be configured later
    @Published var availableModels: [ModelInfo] = []
    @Published var selectedModelId: String? = nil
    @Published var isLoadingModels: Bool = false
    @Published var connectionError: String? = nil
    // ---------------------------------

    private var apiTask: Task<Void, Never>? = nil // To manage the streaming task

    init() {
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

        // Prepare request
        let requestBody = ChatCompletionRequest(model: modelId, messages: history)
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
        var tokenCount = 0 // <<< Renamed from charCount
        
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
            for try await line in bytes.lines {
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
            
        } catch {
            if !Task.isCancelled {
                 connectionError = "Network error during chat: \(error.localizedDescription)"
             }
        }
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
 