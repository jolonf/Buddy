import SwiftUI

// MARK: - Message Row View
struct ChatMessageRow: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            messageContentView()
            if message.role == .assistant || message.role == .system { Spacer() }
        }
    }
    
    @ViewBuilder
    private func messageContentView() -> some View {
        switch message.role {
        case .assistant:
            if let actionView = assistantActionView(for: message) {
                actionView
            } else {
                assistantMessageView(for: message)
            }
        case .user:
            userMessageView(for: message)
        case .system:
            // System messages are not displayed as they are only used for the system prompt
            EmptyView()
        }
    }
}

// MARK: - Message Type Views
private extension ChatMessageRow {
    func userMessageView(for message: ChatMessage) -> some View {
        Text(.init(message.content))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .textSelection(.enabled)
    }
    
    func assistantMessageView(for message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let (thinkingContent, remainingContent) = parseThinkingBlock(message.content) {
                // Display thinking block with special styling
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)
                    
                    Text(.init(thinkingContent))
                        .italic()
                        .foregroundColor(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }
                .padding(.bottom, 4)
                
                // Display remaining content if any
                if !remainingContent.isEmpty {
                    Text(.init(remainingContent))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .textSelection(.enabled)
                }
            } else {
                // Regular message without thinking block
                Text(.init(message.content))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .textSelection(.enabled)
            }
            
            MessageStatsView(message: message)
        }
    }
    
    private func parseThinkingBlock(_ content: String) -> (thinking: String, remaining: String)? {
        // Look for <think> at the start of the content
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.hasPrefix("<think>") else {
            return nil
        }
        
        // Check if there's a closing tag
        if let endTagRange = trimmedContent.range(of: "</think>") {
            // Complete thinking block - extract content and remaining text
            let thinkingStart = trimmedContent.index(trimmedContent.startIndex, offsetBy: "<think>".count) // Skip "<think>"
            let thinkingContent = String(trimmedContent[thinkingStart..<endTagRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let remainingStart = endTagRange.upperBound
            let remainingContent = String(trimmedContent[remainingStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return (thinkingContent, remainingContent)
        } else {
            // Incomplete thinking block - treat entire content as thinking
            let thinkingStart = trimmedContent.index(trimmedContent.startIndex, offsetBy: "<think>".count) // Skip "<think>"
            let thinkingContent = String(trimmedContent[thinkingStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return (thinkingContent, "")
        }
    }
}

// MARK: - Action View
private extension ChatMessageRow {
    func assistantActionView(for message: ChatMessage) -> AnyView? {
        guard let (_, range, parsedAction) = findActionInMessage(message) else {
            return nil
        }
        
        let precedingText = message.content[..<range.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                if !precedingText.isEmpty {
                    Text(.init(precedingText))
                        .padding(.horizontal, 5)
                        .padding(.bottom, 4)
                        .textSelection(.enabled)
                }
                
                ActionContentView(
                    action: parsedAction,
                    message: message,
                    actionRange: range
                )
                
                MessageStatsView(message: message)
            }
            .padding(.vertical, 4)
        )
    }
    
    private func findActionInMessage(_ message: ChatMessage) -> (String, Range<String.Index>, ParsedAction)? {
        for line in message.content.split(whereSeparator: \.isNewline) {
            let lineString = line.description.trimmingCharacters(in: .whitespaces)
            if lineString.hasPrefix("ACTION:"),
               let parsedAction = lineString.parseAsAction(),
               let range = message.content.range(of: lineString) {
                return (lineString, range, parsedAction)
            }
        }
        return nil
    }
}

// MARK: - Action Content View
private struct ActionContentView: View {
    let action: ParsedAction
    let message: ChatMessage
    let actionRange: Range<String.Index>
    
    var body: some View {
        if action.name == "EDIT_FILE" {
            editFileContentView
        } else {
            standardActionView
        }
    }
    
    private var standardActionView: some View {
        Text(formatActionMessage(action))
            .italic()
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .textSelection(.enabled)
    }
    
    private var editFileContentView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatActionMessage(action))
                .italic()
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            
            if let content = extractEditFileContent() {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                    .textSelection(.enabled)
            }
        }
    }
    
    private func extractEditFileContent() -> String? {
        let searchRange = actionRange.upperBound..<message.content.endIndex
        guard let contentStart = message.content.range(of: "CONTENT_START", options: [], range: searchRange)?.upperBound,
              let contentEnd = message.content.range(of: "CONTENT_END", options: [], range: contentStart..<message.content.endIndex)?.lowerBound else {
            return nil
        }
        
        return String(message.content[contentStart..<contentEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Message Stats View
private struct MessageStatsView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(spacing: 10) {
            if let ttft = message.promptTime {
                StatText(format: "TTFT: %.3fs", value: ttft)
            }
            if let tokenCount = message.tokenCount,
               let generationTime = message.generationTime,
               generationTime > 0 {
                StatText(format: "TPS: %.1f", value: Double(tokenCount) / generationTime)
            }
            if let promptTokens = message.promptTokenCount {
                StatText("Prompt: \(promptTokens)")
            }
            if let generationTokens = message.tokenCount {
                StatText("Gen: \(generationTokens)")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.leading, 5)
    }
}

// MARK: - Helper Views
private struct StatText: View {
    let format: String
    let value: CVarArg
    
    init(format: String, value: CVarArg) {
        self.format = format
        self.value = value
    }
    
    init(_ text: String) {
        self.format = "%@"
        self.value = text
    }
    
    var body: some View {
        Text(String(format: format, value))
    }
}

// MARK: - Action Message Formatting
private func formatActionMessage(_ action: ParsedAction) -> String {
    switch action.name {
    case "READ_FILE":
        return "Reading file `\(action.parameters["path"] ?? "(unknown path)")`..."
    case "LIST_DIR":
        return "Listing directory `\(action.parameters["path"] ?? ".")`..."
    case "EDIT_FILE":
        return "Editing file `\(action.parameters["path"] ?? "(unknown path)")`..."
    case "RUN_COMMAND":
        return "Running command `\(action.parameters["command"] ?? "(unknown command)")`..."
    default:
        return "Performing action `\(action.name)`..."
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        VStack(alignment: .leading) {
            ChatMessageRow(message: ChatMessage(role: .user, content: "Hello there!"))
            ChatMessageRow(message: ChatMessage(role: .assistant, content: "Hi! How can I help?", ttft: 0.123, tps: 55.6))
            ChatMessageRow(message: ChatMessage(role: .system, content: "System prompt loaded."))
            ChatMessageRow(message: ChatMessage(role: .assistant, content: "Okay, I will read the file.\nACTION: READ_FILE(path='Sources/Test.swift')"))
            ChatMessageRow(message: ChatMessage(role: .assistant, content: "ACTION: LIST_DIR(path='.')"))
            ChatMessageRow(message: ChatMessage(
                role: .assistant,
                content: "I will edit the file.\nACTION: EDIT_FILE(path='README.md')\nCONTENT_START\n# Updated Readme\nNew content here.\nCONTENT_END\nThis is the final response."
            ))
        }
        .padding()
    }
} 