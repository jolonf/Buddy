import Foundation

// MARK: - Data Structures for Remote API (Ollama/LM Studio Compatible)

/// Represents the overall structure of the response from `/v1/models`
struct ModelListResponse: Codable {
    let data: [ModelInfo]
}

/// Represents a single model entry in the list from the remote API
struct ModelInfo: Codable, Identifiable { // Identifiable for ForEach
    let id: String // The model ID/name string
}

/// Represents the request body for `/v1/chat/completions`
struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage] // Use existing ChatMessage struct
    let stream: Bool = true // Always stream for this app
    let stream_options: [String: Bool]? = ["include_usage": true]
    // Add other parameters like temperature, max_tokens if needed later
}

/// Represents a chunk of data received in the SSE stream from the remote API
struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let role: ChatMessage.Role? // Use ChatMessage.Role here
            let content: String? // The actual token
        }
        let delta: Delta
        let finish_reason: String? // Indicates end of stream
    }

    // Define the nested Usage struct (as returned by Ollama/LM Studio)
    struct Usage: Decodable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int

        // Non-standard properties
        let prompt_time: Double?
        let generation_time: Double?
    }

    let id: String // Chunk ID
    let object: String // Type of object (e.g., "chat.completion.chunk")
    let created: Int // Timestamp
    let model: String // Model used
    let choices: [Choice]
    let usage: Usage? // Usage can be optional, often appears in the last chunk
} 