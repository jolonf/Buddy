import Foundation

// Need to make ChatMessage accessible.
struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable, Hashable { // Ensure Role is Hashable
        case system
        case user
        case assistant
        // case tool // If you add tool roles later
    }

    let id: UUID // REMOVE = UUID() - ID is set in init
    var role: Role
    var content: String

    // Optional metadata fields added during processing
    var ttft: TimeInterval? = nil // Time To First Token
    var tps: Double? = nil      // Tokens Per Second
    var promptTokenCount: Int? = nil
    var tokenCount: Int? = nil  // Completion tokens
    var promptTime: Double? = nil
    var generationTime: Double? = nil

    // Explicit initializer to handle ID generation and allow default generation
    init(id: UUID = UUID(), role: Role, content: String, ttft: TimeInterval? = nil, tps: Double? = nil, promptTokenCount: Int? = nil, tokenCount: Int? = nil, promptTime: Double? = nil, generationTime: Double? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.ttft = ttft
        self.tps = tps
        self.promptTokenCount = promptTokenCount
        self.tokenCount = tokenCount
        self.promptTime = promptTime
        self.generationTime = generationTime
    }

    // Codable conformance is handled automatically for basic properties.
    // If you have complex properties that aren't Codable, you'd need custom coding keys/logic.
} 