import Foundation

// Structure to hold parsed action details
struct ParsedAction { // Make it public/internal
    let name: String
    let parameters: [String: String]
    let multiLineContent: String? // Content for EDIT_FILE
}

/// Represents a single message in the chat history.
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID = UUID()
    let role: Role
    var content: String

    // Performance Stats (local usage only, not part of API payload)
    var ttft: TimeInterval? = nil // Time To First Token (in seconds)
    var tokenCount: Int? = nil    // Approx. Tokens received (assuming 1 per non-empty chunk)
    var tps: Double? = nil        // Approx. Tokens Per Second

    // The API expects roles as lowercased strings.
    enum Role: String, Codable, Equatable {
        case user
        case assistant
        case system
        // Add other roles like 'system' if needed later
    }
    
    // --- Codable Conformance --- 
    // Only encode/decode properties needed for the API request.
    enum CodingKeys: String, CodingKey {
        case role
        case content
        // id, ttft, tokenCount, tps are intentionally omitted
    }
    
    // We might need a custom init(from decoder:) if we add more complex non-API fields later
    // No custom encode(to encoder:) needed as default works for role/content
}
