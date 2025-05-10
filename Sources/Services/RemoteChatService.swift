import Foundation
import SwiftUI // For @MainActor

/// Service responsible for communicating with a remote LLM API (Ollama/LM Studio compatible).
class RemoteChatService: ChatService, @unchecked Sendable {

    private let serverURL: String
    private var currentTask: Task<Void, Never>? = nil

    init(serverURL: String) {
        self.serverURL = serverURL
    }

    // MARK: - ChatService Protocol Implementation

    func fetchAvailableModels() async throws -> [CombinedModelInfo] {
        // TODO: Move logic from ChatViewModel.fetchModels here
        print("DEBUG: fetchAvailableModels() called in RemoteChatService")
        // Placeholder implementation:
        guard let url = URL(string: serverURL + "/v1/models") else {
            throw URLError(.badURL) // Or a custom error
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            // Define a proper error type later
            throw NSError(domain: "RemoteChatService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(statusCode)"])
        }

        do {
            let decodedResponse = try JSONDecoder().decode(ModelListResponse.self, from: data)
            // Map ModelInfo to CombinedModelInfo
            let combinedModels = decodedResponse.data.map {
                CombinedModelInfo(id: "remote:\($0.id)", displayName: $0.id, type: .remote)
            }
            return combinedModels
        } catch {
            print("Decoding Error in fetchAvailableModels: \(error)")
            throw error // Re-throw decoding error
        }
    }

    func sendMessage(
        history: [ChatMessage],
        systemPrompt: String,
        model: CombinedModelInfo,
        interactionMode: InteractionMode,
        additionalContext: [String: ContextValue]? = nil
    ) -> AsyncThrowingStream<ChatStreamUpdate, Error> {
        // TODO: Move streaming logic from ChatViewModel.performStreamingRequest here
        print("DEBUG: sendMessage() called in RemoteChatService for model \(model.id)")

        // Basic stream structure - replace with actual implementation
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // --- Prepare Request --- (Logic moved from ChatViewModel)
                    var messagesForAPI: [ChatMessage] = []
                    messagesForAPI.append(ChatMessage(role: .system, content: systemPrompt))
                    messagesForAPI.append(contentsOf: history)

                    let requestBody = ChatCompletionRequest(model: model.id, messages: messagesForAPI)
                    guard let url = URL(string: serverURL + "/v1/chat/completions") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(requestBody)

                    let requestStartTime = Date()
                    var firstTokenTime: Date? = nil
                    var tokenCount = 0

                    // --- Perform Streaming Request --- (Logic moved from ChatViewModel)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw NSError(domain: "RemoteChatService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Chat Request Failed: \(statusCode)"])
                    }

                    // --- Process Stream --- (Logic moved from ChatViewModel)
                    for try await line in bytes.lines {
                        if line.hasPrefix("data:"), let data = line.dropFirst(6).data(using: .utf8) {
                            if data.isEmpty || data == Data("[DONE]".utf8) { break }

                            do {
                                let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)

                                if let deltaContent = chunk.choices.first?.delta.content, !deltaContent.isEmpty {
                                    if firstTokenTime == nil {
                                        firstTokenTime = Date()
                                        let ttft = firstTokenTime!.timeIntervalSince(requestStartTime)
                                        continuation.yield(.firstTokenTime(ttft))
                                    }
                                    tokenCount += 1 // Approximate token count
                                    continuation.yield(.contentDelta(deltaContent))
                                }

                                if let usage = chunk.usage {
                                    // Map StreamChunk.Usage to ChatUsageMetrics
                                    let metrics = ChatUsageMetrics(
                                        prompt_tokens: usage.prompt_tokens,
                                        completion_tokens: usage.completion_tokens,
                                        total_tokens: usage.total_tokens,
                                        prompt_time: usage.prompt_time,
                                        generation_time: usage.generation_time
                                    )
                                    continuation.yield(.usage(metrics))
                                }

                                // Finish reason doesn't necessarily mean end of stream if usage comes later
                                // if let _ = chunk.choices.first?.finish_reason { }

                            } catch {
                                print("Failed to decode stream chunk: \(error), Line: \(line)")
                                continuation.yield(.error(error))
                                // Decide whether to break or continue
                            }
                        }
                    }

                    // --- Final Metrics --- (Logic moved from ChatViewModel)
                    let finishTime = Date()
                    let duration = finishTime.timeIntervalSince(firstTokenTime ?? requestStartTime)
                    var tps: Double? = nil
                    if duration > 0.01 && tokenCount > 0 {
                        tps = Double(tokenCount) / duration
                    }
                    continuation.yield(.finalMetrics(tps: tps, tokenCount: tokenCount))

                    // --- Finish Stream --- 
                    continuation.finish()

                } catch {
                    // Handle cancellation error specifically
                    if Task.isCancelled && error is CancellationError {
                        print("RemoteChatService Task Cancelled")
                        continuation.finish() // Finish normally on cancellation
                    } else {
                        print("Error in RemoteChatService sendMessage task: \(error)")
                        continuation.finish(throwing: error)
                    }
                }
            }
            // Store the task for cancellation
            self.currentTask = task
            // Set up cancellation handler
            // Only cancel the task in the @Sendable closure to avoid capturing self
            continuation.onTermination = { @Sendable _ in
                print("Stream terminated. Cancelling remote task.")
                task.cancel()
            }
            // After the stream finishes, clear currentTask on the main actor
            Task { @MainActor in
                self.currentTask = nil
            }
        }
    }

    func cancelCurrentRequest() {
        print("DEBUG: cancelCurrentRequest() called in RemoteChatService")
        currentTask?.cancel()
        currentTask = nil
    }

    // loadLocalModel and unloadLocalModel use the default implementation from the protocol extension
} 