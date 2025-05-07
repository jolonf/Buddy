import Foundation

/// Represents usage metrics provided by the LLM service.
/// Placeholder until StreamChunk is moved or refactored.
struct ChatUsageMetrics: Decodable { // Make it Decodable for potential future use
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int

    // Non-standard properties that might be available
    let prompt_time: Double?
    let generation_time: Double?
}

/// Represents information about an available model, local or remote.
struct CombinedModelInfo: Identifiable, Hashable {
    let id: String // Usually the unique model identifier string
    let displayName: String // A user-friendly name
    enum ModelType { case local, remote }
    let type: ModelType
    // Add other potential fields if needed, e.g., source (huggingface path for local)
}

/// Represents updates received during a chat streaming session.
enum ChatStreamUpdate {
    case contentDelta(String)
    case usage(ChatUsageMetrics) // Using the placeholder struct
    case firstTokenTime(TimeInterval) // Time To First Token (TTFT)
    case finalMetrics(tps: Double?, tokenCount: Int) // Tokens Per Second, total completion tokens
    case error(Error)
}

/// Protocol defining the interface for interacting with a chat service (local or remote).
protocol ChatService {
    /// Fetches the list of models available from the service.
    func fetchAvailableModels() async throws -> [CombinedModelInfo]

    /// Sends chat messages and returns a stream of updates.
    /// - Parameters:
    ///   - history: The conversation history up to the point of the new message.
    ///   - systemPrompt: The system prompt to use for the interaction.
    ///   - model: The specific model (local or remote) to use.
    ///   - interactionMode: The current mode (e.g., ask or agent).
    /// - Returns: An asynchronous throwing stream of `ChatStreamUpdate`.
    func sendMessage(
        history: [ChatMessage],
        systemPrompt: String,
        model: CombinedModelInfo,
        interactionMode: InteractionMode // Need InteractionMode definition available
    ) -> AsyncThrowingStream<ChatStreamUpdate, Error>

    /// Cancels any ongoing request associated with the service.
    func cancelCurrentRequest()

    // Optional methods for local model management
    // Implementers can provide default empty implementations or throw errors if not applicable.

    /// Loads a specific local model into memory.
    /// Default implementation could do nothing or throw.
    func loadLocalModel(_ model: CombinedModelInfo) async throws

    /// Unloads the currently loaded local model from memory.
    /// Default implementation could do nothing.
    func unloadLocalModel() async
}

// Provide default implementations for optional methods
extension ChatService {
    func loadLocalModel(_ model: CombinedModelInfo) async throws {
        // Default: Do nothing or throw an error indicating not supported
        print("Warning: loadLocalModel not implemented by \(type(of: self))")
    }

    func unloadLocalModel() async {
        // Default: Do nothing
        print("Warning: unloadLocalModel not implemented by \(type(of: self))")
    }
}

// NOTE: Ensure `ChatMessage` and `InteractionMode` are accessible here.
// If they are defined in ChatViewModel, they might need to be moved to a shared location or made public.
// For now, assume they are accessible. You might need to add: import struct ModuleName.ChatMessage etc.
// Or move their definitions. Let's assume they are defined elsewhere and accessible for now.

// Need to make InteractionMode accessible. We can define it here or move it.
// Let's redefine it here for now to make this file self-contained temporarily.
// TODO: Move InteractionMode to a shared location if not already done.

// Need to make ChatMessage accessible. Let's redefine its structure here temporarily.
// TODO: Move ChatMessage to a shared location if not already done.

// Custom initializer if needed, or rely on memberwise

// Custom initializer if needed, or rely on memberwise
