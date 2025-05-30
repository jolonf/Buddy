import SwiftUI

// Renamed from ContentView
struct ChatView: View {
    // Instantiate the ViewModel
    // NOTE: Should this ViewModel be passed in or stay @StateObject?
    // For now, keep as StateObject, but might need refactoring later
    // if state needs to be shared more broadly (e.g., with FolderView)
    @EnvironmentObject var viewModel: ChatViewModel
    // Also need FolderViewModel for the Agent Mode toggle's context (though not used directly yet)
    @EnvironmentObject var folderViewModel: FolderViewModel
    // Focus state for the chat input field
    @FocusState private var isChatInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // --- Top Bar: Connection Status & Model Selection ---
            VStack(spacing: 4) {
                // Only show error if it's a local model loading error
                if case .error(let error) = viewModel.localModelLoadingState {
                    Text("Local Model Error: \(error)")
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

                // HStack with Picker and Refresh Button removed from here
            }
            .padding(.top, 8)
            // Removed bottom padding from top section
            
            // Scrollable chat message area
            ScrollView {
                ScrollViewReader { proxy in // Allows scrolling to the bottom
                    LazyVStack(alignment: .leading) {
                        // Add Chat header at the top of the scroll view
                        Text("Chat")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8) // Add some space below the title
                            .frame(maxWidth: .infinity, alignment: .center) // Center the title
                        
                        ForEach(viewModel.messages) { message in
                            // Use renamed message row view
                            ChatMessageRow(message: message)
                                .id(message.id) // ID for scrolling
                        }
                        
                        // --- Inline Loading Indicator or Typing Indicator ---
                        if case .loading(let progress) = viewModel.localModelLoadingState {
                            HStack(spacing: 8) {
                                if let progress = progress {
                                    ProgressView(value: progress)
                                        .frame(width: 80)
                                    Text(String(format: "Loading model... %.0f%%", progress * 100))
                                        .foregroundColor(.secondary)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading model...")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("loadingIndicator")
                            .transition(.opacity)
                        } else if viewModel.isAwaitingFirstToken {
                            TypingIndicatorView()
                                .id("typingIndicator") // Add ID for potential scrolling target
                                .transition(.opacity) // Fade in/out
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    // Scroll to bottom when messages change OR content updates
                    .onChange(of: viewModel.scrollTrigger) { _, _ in // Observe scrollTrigger
                        if let lastMessageId = viewModel.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastMessageId, anchor: .bottom)
                            }
                        } else if case .loading = viewModel.localModelLoadingState {
                            withAnimation {
                                proxy.scrollTo("loadingIndicator", anchor: .bottom)
                            }
                        } else if viewModel.isAwaitingFirstToken {
                            withAnimation {
                                proxy.scrollTo("typingIndicator", anchor: .bottom)
                            }
                        }
                    }
                    // --- ADD: Scroll when typing indicator appears ---
                    .onChange(of: viewModel.isAwaitingFirstToken) { _, isAwaiting in
                        if isAwaiting {
                            // Scroll to the indicator when it appears
                            withAnimation {
                                proxy.scrollTo("typingIndicator", anchor: .bottom)
                            }
                        }
                        // No need to scroll when it disappears, the message scroll will handle it
                    }
                    // -----------------------------------------------
                }
            }
            .id("MessageListBottom") // For scrolling

            // --- Agent Mode and Thinking Toggles --- 
            HStack {
                Toggle("Agent Mode", isOn: viewModel.isAgentModeBinding)
                    .toggleStyle(.checkbox) // Use checkbox style on macOS
                Toggle("Thinking", isOn: viewModel.isThinkingEnabledBinding)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal)
            .padding(.top, 8) // Add top padding
            .padding(.bottom, 4)

            // Divider and Picker/Refresh row moved above input
            Divider()
            HStack {
                let remoteModels = viewModel.availableModels.filter { $0.type == .remote }
                let localModels = viewModel.availableModels.filter { $0.type == .local }
                Picker("Selected Model", selection: $viewModel.selectedModelId) {
                    if !remoteModels.isEmpty {
                        Section(header: HStack {
                            Text("Remote Models")
                            if viewModel.connectionError?.contains("Remote:") == true {
                                Text("(Unavailable)").foregroundColor(.gray).font(.caption)
                            }
                        }) {
                            ForEach(remoteModels) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                    }
                    if !localModels.isEmpty {
                        Section(header: Text("Local Models")) {
                            ForEach(localModels) { model in
                                HStack {
                                    Text(model.displayName)
                                    if viewModel.selectedModelId == model.id {
                                        switch viewModel.localModelLoadingState {
                                        case .loading:
                                            ProgressView().scaleEffect(0.6)
                                        case .error(let msg):
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                                            Text(msg).foregroundColor(.red).font(.caption)
                                        case .loaded(let loadedModel) where loadedModel.id == model.id:
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                        default:
                                            EmptyView()
                                        }
                                    }
                                }
                                .tag(model.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .disabled(viewModel.isLoadingModels || viewModel.availableModels.isEmpty)
                // Only disable if loading or no models at all
                Button {
                    Task { await viewModel.fetchModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingModels)
            }
            .padding(.horizontal) // Only horizontal padding now
            .padding(.top, 8) // Add some top padding
            .padding(.bottom, 4) // Add some bottom padding before input
            
            Divider() // Add divider between picker and input

            // Input area
            HStack {
                TextField("Type your message...", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit(viewModel.sendMessage)
                    .focused($isChatInputFocused) // Bind focus state

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
            // Add top padding to input row
            .padding(.top, 8) 
            .padding([.horizontal, .bottom])
        }
        .frame(minHeight: 300)
        .onAppear { // Set initial focus when the view appears
            isChatInputFocused = true
        }
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

// MARK: - Typing Indicator View

private struct TypingIndicatorView: View {
    // @State private var animationPhase: Double = 0.0
    private let dotCount = 3
    // private let animationDuration = 0.9
    @State private var isAnimating = false // State to trigger animation

    var body: some View {
        HStack(spacing: 5) { // Increased spacing slightly
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    // .foregroundColor(.secondary.opacity(calculateOpacity(index: index)))
                    .foregroundColor(.secondary)
                    .scaleEffect(isAnimating ? 1.0 : 0.5) // Animate scale
                    .animation(
                        .easeInOut(duration: 0.4) // Faster pulse
                        .repeatForever(autoreverses: true)
                        .delay(0.1 * Double(index)), // Stagger animation start
                        value: isAnimating
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading) // Align left like assistant message
        .padding(.horizontal) // Match message padding
        .padding(.vertical, 8)
        .onAppear {
            isAnimating = true // Start animation on appear
            // Simple repeating animation using phase
            // // Schedule animation slightly differently to avoid immediate jump
            // DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { 
            //      withAnimation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)) {
            //          animationPhase = 1.0
            //      }
            // }
        }
        // No need for onDisappear reset with this animation approach
        // .onDisappear {
        //      // Reset animation phase if needed, though it might not be strictly necessary
        //      animationPhase = 0.0 
        // }
    }

    // Calculate opacity based on index and overall animation phase
    // private func calculateOpacity(index: Int) -> Double {
    //     // Create a phase offset for each dot so they don't animate identically
    //     let phaseShift = Double(index) / Double(dotCount)
    //     // Calculate the current phase for this specific dot (0.0 to 1.0)
    //     let dotPhase = (animationPhase + phaseShift).truncatingRemainder(dividingBy: 1.0)
    //     // Use a curve (e.g., parabola) to make opacity fade in/out smoothly
    //     // Center the peak opacity at phase 0.5
    //     let centeredPhase = abs(dotPhase - 0.5) * 2 // Maps 0->0.5->1 to 1->0->1
    //     let opacity = 1.0 - centeredPhase // Invert: 0->1->0
    //     // Add a minimum opacity so dots don't disappear completely
    //     return 0.3 + (0.7 * opacity)
    // }
}

#Preview {
    // Create dummy view models for the preview
    let folderVM = FolderViewModel()
    let commandRunnerVM = CommandRunnerViewModel() // Create dummy command runner
    // Create a dummy remote service for the preview
    let remoteService = RemoteChatService(serverURL: "http://localhost:1234")
    let localService = LocalChatService()
    // Update ChatViewModel initialization to include the service
    let chatVM = ChatViewModel(folderViewModel: folderVM, commandRunnerViewModel: commandRunnerVM, remoteChatService: remoteService, localChatService: localService)
    
    ChatView()
        // Provide ALL required view models to the environment for the preview
        .environmentObject(folderVM)
        .environmentObject(chatVM) // <<< Add ChatViewModel injection
        .environmentObject(commandRunnerVM) // <<< Add CommandRunnerViewModel injection (if needed by subviews)
} 