import SwiftUI

// --- Remove Subview for History Entries ---
// struct CommandHistoryEntryView: View { ... }
// ------------------------------------

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
                    LazyVStack(alignment: .leading, spacing: 8) { // Use LazyVStack for rows
                        // Add Console Output header
                        Text("Console Output")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4) // Add some space below the title
                            .frame(maxWidth: .infinity, alignment: .center) // Center the title
                        
                        // Iterate through history entries
                        ForEach(viewModel.history) { entry in
                            // Inline the VStack again
                            VStack(alignment: .leading, spacing: 2) { 
                                // Display command line
                                Text("$ \(entry.command)")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium) // Slightly bolder for command
                                    .foregroundColor(.secondary) // Dim the command slightly
                                
                                // Display output if not empty
                                if !entry.output.isEmpty {
                                    Text(entry.output)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                
                                // Display exit code if available
                                if let exitCode = entry.exitCode {
                                    Text("Exit Code: \(exitCode)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(exitCode == 0 ? .green : .red)
                                }
                            }
                            .padding(.bottom, 8) // Space between entries
                            .id(entry.id) // Use entry ID for scrolling
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
                    
                }
                .frame(maxHeight: .infinity)
                // --- Revert onChange for scrolling to watch history count --- 
                .onChange(of: viewModel.history) { // Observe history array changes
                    // Scroll to bottom when history changes
                    if let lastEntryId = viewModel.history.last?.id {
                        withAnimation {
                            scrollViewProxy.scrollTo(lastEntryId, anchor: .bottom)
                        }
                    }
                }
            } // --- End ScrollViewReader ---
            
            Divider()
            
            // Input and Control Area
            HStack {
                TextField("Enter terminal command...", text: $viewModel.commandInput) // Updated placeholder
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