import Foundation

/// Represents a single message in the chat history.
struct ChatMessage: Identifiable, Codable {
    let id: UUID = UUID()
    let role: Role
    var content: String
    
    // Performance Stats (local usage only, not part of API payload)
    var ttft: TimeInterval? // Time To First Token
    var tokenCount: Int?    // Approx. Tokens received (assuming 1 per non-empty chunk)
    var tps: Double?        // Approx. Tokens Per Second

    // The API expects roles as lowercased strings.
    enum Role: String, Codable { 
        case user
        case assistant
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