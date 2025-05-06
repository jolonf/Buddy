import SwiftUI

struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            // Align message based on role
            if message.role == .user {
                Spacer() // Push user messages to the right
            }

            // Render the appropriate view based on message type
            messageContentView()

            if message.role == .assistant || message.role == .system {
                Spacer() // Push assistant/system messages to the left
            }
        }
    }

    // MARK: - View Builder Helpers

    @ViewBuilder
    private func messageContentView() -> some View {
        // Prioritize checking for assistant actions
        if message.role == .assistant,
           let actionView = assistantActionView(for: message) {
            actionView // Display the custom action view if found
        } else if message.role == .user {
            userMessageView(for: message)
        } else {
            // Default view for regular assistant or system messages
            assistantOrSystemMessageView(for: message)
        }
    }

    /// Attempts to render the view for an assistant message containing an ACTION.
    /// Returns nil if no valid ACTION is found or it's not an assistant message.
    private func assistantActionView(for message: ChatMessage) -> AnyView? {
        // --- Try to find the first valid ACTION line --- 
        var actionLine: String? = nil
        var actionLineRange: Range<String.Index>? = nil

        for line in message.content.split(whereSeparator: \.isNewline) {
            // Use description property for String representation
            let lineString = line.description.trimmingCharacters(in: .whitespaces)
            if lineString.hasPrefix("ACTION:"), lineString.parseAsAction() != nil {
                actionLine = lineString
                actionLineRange = message.content.range(of: lineString)
                break // Use the first one found
            }
        }
        // ---------------------------------------------
        
        // If we found and parsed an action line successfully
        guard let line = actionLine, let range = actionLineRange, let parsedAction = line.parseAsAction() else {
            return nil // Not a valid action message
        }
        
        // --- Extract preceding text ---
        let precedingText = message.content[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        // ----------------------------

        // --- Create the combined view --- 
        let combinedView = VStack(alignment: .leading, spacing: 4) {
            // 1. Display preceding text if it exists
            if !precedingText.isEmpty {
                Text(.init(precedingText))
                    .padding(.horizontal, 5) // Match default assistant padding
                    .padding(.bottom, 4)    // Add spacing before action
                    .textSelection(.enabled)
            }

            // 2. Render the action display
            // --- Render Action Display (ignoring text before the action line) ---
            if parsedAction.name == "EDIT_FILE" {
                // EDIT_FILE specific rendering (Header + Content)
                VStack(alignment: .leading, spacing: 4) {
                    Text(.init(formatActionMessage(parsedAction)))
                        .italic()
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    // Find CONTENT_START *after* the action line's range
                    let searchRangeAfterAction = range.upperBound..<message.content.endIndex
                    if let contentStartMarkerRange = message.content.range(of: "CONTENT_START", options: [], range: searchRangeAfterAction) {
                        // Find content after marker (skip potential newline)
                        if let contentActualStart = message.content.rangeOfCharacter(from: .newlines.inverted, options: [], range: contentStartMarkerRange.upperBound..<message.content.endIndex)?.lowerBound {
                            let contentToEnd = String(message.content[contentActualStart...])
                            // Find CONTENT_END within that remaining part
                            let contentEndIndex = contentToEnd.range(of: "\nCONTENT_END")?.lowerBound
                                                  ?? contentToEnd.range(of: "CONTENT_END")?.lowerBound
                                                  ?? contentToEnd.endIndex
                            let finalContentToShow = String(contentToEnd[..<contentEndIndex])
                                                        .trimmingCharacters(in: .whitespacesAndNewlines)

                            if !finalContentToShow.isEmpty {
                                Text(finalContentToShow)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            } else {
                // Standard summary for other actions (READ_FILE, LIST_DIR)
                Text(.init(formatActionMessage(parsedAction)))
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .textSelection(.enabled)
            }

            statsView(for: message)
        }

        return AnyView(combinedView.padding(.vertical, 4)) // Add overall padding to the combined view
    }

    /// Renders the standard view for a user message.
    @ViewBuilder
    private func userMessageView(for message: ChatMessage) -> some View {
        Text(message.content)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .textSelection(.enabled)
    }

    /// Renders the default view for assistant (non-action) or system messages.
    @ViewBuilder
    private func assistantOrSystemMessageView(for message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) { 
            Text(.init(message.content)) // Use .init for potential Markdown
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .textSelection(.enabled)
            // Show stats only for assistant messages
            if message.role == .assistant {
                statsView(for: message)
            }
        }
    }

    /// Renders stats for assistant messages like TTFT, TPS, and prompt tokens.
    @ViewBuilder
    private func statsView(for message: ChatMessage) -> some View {
        HStack(spacing: 10) {
            if let ttft = message.promptTime {
                Text(String(format: "TTFT: %.3fs", ttft))
            }
            if let tps = message.tps {
                Text(String(format: "TPS: %.1f", tps))
            }
            if let tokenCount = message.tokenCount, let generationTime = message.generationTime,
               generationTime > 0 {
                Text(String(format: "TPS2: %.1f", Double(tokenCount) / generationTime))
            }
            if let promptTokens = message.promptTokenCount {
                Text("Prompt: \(promptTokens)")
            }
            if let generationTokens = message.tokenCount {
                Text("Gen: \(generationTokens)")
            }       
         }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.leading, 5) // Align roughly with text padding
    }

    // MARK: - Helpers (Existing)

    // Helper to format action messages
    private func formatActionMessage(_ action: ParsedAction) -> String {
        switch action.name {
        case "READ_FILE":
            let path = action.parameters["path"] ?? "(unknown path)"
            return "Reading file `\(path)`..."
        case "LIST_DIR":
            let path = action.parameters["path"] ?? "."
            return "Listing directory `\(path)`..."
        case "EDIT_FILE":
            let path = action.parameters["path"] ?? "(unknown path)"
            return "Editing file `\(path)`..."
        case "RUN_COMMAND":
            let command = action.parameters["command"] ?? "(unknown command)"
            // Keep command short for display if needed, or show full?
            // Let's show full for now, capped by UI if necessary.
            return "Running command `\(command)`..."
        default:
            return "Performing action `\(action.name)`..."
        }
    }
}

#Preview {
    // --- Sample Messages for Preview --- 
    let userMsg = ChatMessage(role: .user, content: "Hello there!")
    let assistantMsg = ChatMessage(role: .assistant, content: "Hi! How can I help?", ttft: 0.123, tps: 55.6)
    let systemMsg = ChatMessage(role: .system, content: "System prompt loaded.")
    let readFileActionMsg = ChatMessage(role: .assistant, content: "Okay, I will read the file.\nACTION: READ_FILE(path='Sources/Test.swift')")
    let listDirActionMsg = ChatMessage(role: .assistant, content: "ACTION: LIST_DIR(path='.')")
    let editFileActionMsg = ChatMessage(
        role: .assistant, 
        content: "I will edit the file.\nACTION: EDIT_FILE(path='README.md')\nCONTENT_START\n# Updated Readme\nNew content here.\nCONTENT_END\nThis is the final response."
    )
    let editFileNoPrecedingText = ChatMessage(
        role: .assistant, 
        content: "ACTION: EDIT_FILE(path='Sources/Another.swift')\nCONTENT_START\nfunc newFunc() { }\nCONTENT_END"
    )
    let runCommandActionMsg = ChatMessage(role: .assistant, content: "ACTION: RUN_COMMAND(command='swift build')")
    
    // --- Preview Layout --- 
    return ScrollView { // Use ScrollView to see multiple messages
        VStack(alignment: .leading) {
            ChatMessageRow(message: userMsg)
            ChatMessageRow(message: assistantMsg)
            ChatMessageRow(message: systemMsg)
            ChatMessageRow(message: readFileActionMsg)
            ChatMessageRow(message: listDirActionMsg)
            ChatMessageRow(message: editFileActionMsg)
            ChatMessageRow(message: editFileNoPrecedingText)
            ChatMessageRow(message: runCommandActionMsg)
        }
        .padding()
    }
} 