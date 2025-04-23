import SwiftUI

struct ContentView: View {
    // Instantiate the ViewModel
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // --- Top Bar: Connection Status & Model Selection ---
            VStack(spacing: 4) {
                if let error = viewModel.connectionError {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding(.horizontal)
                } else if viewModel.isLoadingModels {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading models...")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Model:")
                    Picker("Selected Model", selection: $viewModel.selectedModelId) {
                        ForEach(viewModel.availableModels) { model in
                            Text(model.id).tag(String?(model.id))
                        }
                    }
                    .labelsHidden() // Hide the picker label itself
                    .disabled(viewModel.isLoadingModels || viewModel.connectionError != nil || viewModel.availableModels.isEmpty)
                    // Consider adding a refresh button
                    Button { 
                        Task { await viewModel.fetchModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingModels)
                }
                .padding(.horizontal)
                
                Divider()
            }
            .padding(.top, 8) // Add some top padding for the new section
            .padding(.bottom, 4)
            
            // Scrollable chat message area
            ScrollView {
                ScrollViewReader { proxy in // Allows scrolling to the bottom
                    LazyVStack(alignment: .leading) {
                        ForEach(viewModel.messages) { message in
                            MessageView(message: message)
                                .id(message.id) // ID for scrolling
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    // Scroll to bottom when messages change
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastMessageId = viewModel.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastMessageId, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack {
                TextField("Type your message...", text: $viewModel.currentInput, axis: .vertical) // Allow vertical expansion
                    .textFieldStyle(.plain)
                    .lineLimit(1...5) // Limit vertical expansion
                    .onSubmit(viewModel.sendMessage) // Send on pressing Enter
                    .disabled(viewModel.isSendingMessage) // Disable while sending

                if viewModel.isSendingMessage {
                    // Show Stop button while sending
                    Button("Stop") {
                        viewModel.cancelStreaming()
                    }
                    .keyboardShortcut(".", modifiers: .command) // Example shortcut
                } else {
                    // Show Send button when not sending
                    Button("Send") {
                        viewModel.sendMessage()
                    }
                    .disabled(viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedModelId == nil)
                    .keyboardShortcut(.return, modifiers: []) // Send on Enter (if not submitting via TextField)
                }
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300) // Give the window a reasonable default size
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Clear Chat", systemImage: "trash") {
                    viewModel.clearChat()
                }
                .help("Clear conversation history")
                .disabled(viewModel.messages.isEmpty || viewModel.isSendingMessage)
            }
        }
    }
}

/// A view to display a single chat message.
struct MessageView: View {
    let message: ChatMessage

    // Computed property handles newline normalization for assistant message display
    private var processedAssistantContent: String {
        guard message.role == .assistant else { return message.content } 
        
        var processed = message.content
        processed = processed.replacingOccurrences(of: "\r\n", with: "\n") // Windows -> Unix
        processed = processed.replacingOccurrences(of: "\r", with: "\n")   // Classic Mac -> Unix
        // Collapse multiple blank lines (might need repeating or regex for >2)
        processed = processed.replacingOccurrences(of: "\n\n", with: "\n") 
        return processed
    }
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer() // Push user messages to the right
            }

            if message.role == .user {
                // Apply bubble style to user messages
                Text(message.content)
                    .padding(10)
                    .background(Color.blue.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .textSelection(.enabled)
            } else {
                // Use processed content for assistant
                VStack(alignment: .leading, spacing: 4) { // Wrap in VStack to place stats below
                    Text(.init(processedAssistantContent))
                        .padding(.horizontal, 5) // Minimal padding
                        .textSelection(.enabled)
                    
                    // Display performance stats if available
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

            if message.role == .assistant {
                Spacer() // Push assistant messages to the left
            }
        }
        .padding(.vertical, 4)
    }
} 