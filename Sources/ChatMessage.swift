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

// MARK: - Action Parsing Extension
extension String {
    /// Attempts to parse the string as an ACTION command.
    /// Returns nil if the string doesn't match the expected format.
    func parseAsAction() -> ParsedAction? {
        let trimmedString = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedString.hasPrefix("ACTION:") else { return nil }

        let actionString = String(trimmedString.dropFirst("ACTION:".count)).trimmingCharacters(in: .whitespaces)

        // Basic parsing - assumes format ACTION_NAME(key='value',key2='value')
        // TODO: Make parsing more robust (e.g., regex)
        guard let openParen = actionString.firstIndex(of: "("),
              let closeParen = actionString.lastIndex(of: ")"),
              openParen < closeParen else { return nil }

        let actionName = String(actionString[..<openParen]).trimmingCharacters(in: .whitespaces)
        let paramsString = String(actionString[actionString.index(after: openParen)..<closeParen])

        var parameters: [String: String] = [:]
        let paramPairs = paramsString.split(separator: ",") // Adjust split if needed
        for pair in paramPairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                // Trim whitespace and potential quotes (' or ")
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\'\""))
                parameters[key] = value
            }
        }
        
        // Note: Multi-line content parsing is handled separately in ChatViewModel 
        // as it requires looking at subsequent lines.
        // This parser only handles the ACTION: line itself.
        return ParsedAction(name: actionName, parameters: parameters, multiLineContent: nil)
    }
} 