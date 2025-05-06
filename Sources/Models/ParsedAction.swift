import Foundation

/// Represents a parsed action command extracted from LLM output.
struct ParsedAction: Hashable {
    let name: String
    let parameters: [String: String]
    // Content specifically for multi-line actions like EDIT_FILE
    let multiLineContent: String?
} 