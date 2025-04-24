import SwiftUI

struct CommandRunnerView: View {
    // Use StateObject for now, will likely change to EnvironmentObject
    // if created higher up as discussed
    @EnvironmentObject var viewModel: CommandRunnerViewModel
    
    // Access FolderViewModel for the current directory
    @EnvironmentObject var folderViewModel: FolderViewModel
    
    // --- Correct FocusState variable ---
    @FocusState private var textFieldIsFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Command Output Area
            // --- Add ScrollViewReader ---
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    // --- Map history entries to a single string --- 
                    Text(viewModel.history.map { entry in
                        var entryString = "$ \(entry.command)\n"
                        entryString += entry.output
                        if !entry.output.isEmpty && !entry.output.hasSuffix("\n") {
                             entryString += "\n" // Ensure newline after output
                        }
                        if let exitCode = entry.exitCode {
                            entryString += "Exit Code: \(exitCode)"
                        }
                        return entryString
                    }.joined(separator: "\n\n")) // Join entries with double newline
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .textSelection(.enabled)
                        .id("logOutput") // --- Add ID ---
                }
                .frame(maxHeight: .infinity)
                // --- Add onChange for scrolling (Use zero-param version for macOS 14+) ---
                .onChange(of: viewModel.history) { 
                    // Scroll to bottom when history changes
                    withAnimation {
                         scrollViewProxy.scrollTo("logOutput", anchor: .bottom)
                    }
                }
            } // --- End ScrollViewReader ---
            
            Divider()
            
            // Input and Control Area
            HStack {
                TextField("Enter command...", text: $viewModel.commandInput)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    // --- Use correct FocusState binding --- 
                    .focused($textFieldIsFocused)
                    .onSubmit {
                        // Run command on submit if not already running
                        if !viewModel.isRunning {
                            // Get current folder URL and pass it
                            if let url = folderViewModel.selectedFolderURL {
                                 viewModel.runCommand(workingDirectory: url)
                                 // --- Set focus back ---
                                 textFieldIsFocused = true
                            } else {
                                // Handle case where no folder is selected (e.g., show alert?)
                                print("Cannot run command: No folder selected.")
                            }
                        }
                    }
                    // Add .onKeyPress here
                    .onKeyPress(keys: [.upArrow, .downArrow], action: { keyPress in
                        if keyPress.key == .upArrow {
                            viewModel.navigateHistoryUp()
                            return .handled // Indicate we handled the key press
                        } else if keyPress.key == .downArrow {
                            viewModel.navigateHistoryDown()
                            return .handled // Indicate we handled the key press
                        }
                        return .ignored // Allow other key presses to function normally
                    })
                    // --- Disable if no folder selected --- 
                    .disabled(folderViewModel.selectedFolderURL == nil)
                
                if viewModel.isRunning {
                    Button("Stop") {
                        viewModel.stopCommand()
                    }
                } else {
                    Button("Run") {
                        // Get current folder URL and pass it
                        if let url = folderViewModel.selectedFolderURL {
                             viewModel.runCommand(workingDirectory: url)
                             // --- Set focus back ---
                             textFieldIsFocused = true
                        } else {
                            // Handle case where no folder is selected (e.g., show alert?)
                            print("Cannot run command: No folder selected.")
                        }
                    }
                    .disabled(viewModel.commandInput.isEmpty || folderViewModel.selectedFolderURL == nil)
                    .keyboardShortcut(.defaultAction)
                }
                
                // Clear Button
                Button {
                    viewModel.clearLog()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear command log")
                .disabled(viewModel.history.isEmpty)

            }
            .padding()
        }
         // Optional: Add min height if needed
        // .frame(minHeight: 150) 
        // --- Add onAppear to set initial focus ---
        .onAppear {
            textFieldIsFocused = true
        }
    }
}

#Preview {
    CommandRunnerView()
        .environmentObject(FolderViewModel()) // Provide dummy FolderVM
        .environmentObject(CommandRunnerViewModel()) // Provide dummy CommandRunnerVM
        .frame(height: 300)
} 