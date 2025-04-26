import SwiftUI

struct ChatMessageRow: View {
    let message: ChatMessage

    // Computed property handles newline normalization for assistant message display
    private var formattedContent: String {
        message.content.replacingOccurrences(of: "\n", with: " ")
    }

    // Helper to format action messages
    private func formatActionMessage(_ action: ParsedAction) -> String {
        let path = action.parameters["path"] ?? "(unknown path)"
        switch action.name {
        case "READ_FILE":
            return "Reading file `\(path)`..."
        case "LIST_DIR":
            return "Listing directory `\(path)`..."
        case "EDIT_FILE":
            return "Editing file `\(path)`..."
        default:
            return "Performing action `\(action.name)`..."
        }
    }
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer() // Push user messages to the right
            }

            Group { // Group to apply common modifiers
                // Check if it's an assistant message containing a parsable ACTION
                if message.role == .assistant, let parsedAction = message.content.parseAsAction() {
                    // Display formatted action text
                    Text(.init(formatActionMessage(parsedAction))) // Use Markdown for backticks
                        .italic()
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5) // Minimal padding like normal assistant msg
                        .padding(.vertical, 4)
                } else if message.role == .user {
                    // Apply bubble style to user messages
                    Text(message.content)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                } else {
                    // Display regular assistant message content
                    // Re-introduce the VStack for potential stats later if needed
                    VStack(alignment: .leading, spacing: 4) { 
                        Text(.init(message.content)) // Use .init for potential Markdown
                            .padding(.horizontal, 5)
                            .padding(.vertical, 4)
                            .textSelection(.enabled)
                        // Re-add performance stats display
                        HStack(spacing: 10) {
                            if let ttft = message.ttft {
                                Text(String(format: "TTFT: %.3fs", ttft))
                            }
                            if let tps = message.tps {
                                Text(String(format: "TPS: %.1f", tps))
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 5) // Align roughly with text padding
                    }
                }
            }

            if message.role == .assistant {
                Spacer() // Push assistant messages to the left
            }
        }
    }
} 