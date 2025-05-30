import SwiftUI

struct FileContentView: View {
    // Observe the ViewModel from the environment
    @EnvironmentObject var viewModel: FileContentViewModel
    // Access the FolderViewModel to know which item is selected
    @EnvironmentObject var folderViewModel: FolderViewModel

    var body: some View {
        VStack(spacing: 0) {
            // --- Content Area ---
            Group { // Group allows applying modifiers conditionally later
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.fileURL != nil {
                    if viewModel.isPlainText {
                        // Display TextEditor for plain text files
                        TextEditor(text: $viewModel.fileContent)
                            .font(.system(.body, design: .monospaced)) // Use monospaced font
                            .onChange(of: viewModel.fileContent) { _, _ in
                                // Check dirty state when content changes
                                viewModel.checkDirtyState()
                            }
                    } else {
                        // Display icon for non-text files
                        VStack {
                            Spacer()
                            if let icon = viewModel.fileIcon {
                                icon
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 64, height: 64)
                            } else {
                                Image(systemName: "doc") // Fallback icon
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 64, height: 64)
                                    .foregroundColor(.secondary)
                            }
                            Text("Cannot display/edit this file type.")
                                .foregroundColor(.secondary)
                                .padding(.top)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // Placeholder when no file is loaded initially
                    Text("Select a file from the sidebar to view its content.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // Watch for changes in the selected item from FolderViewModel
        .onChange(of: folderViewModel.selectedItem) { _, newItem in
            handleSelectionChange(item: newItem)
        }
        // Attach save command logic directly
        // Use a hidden button conceptually triggered by the shortcut
        .background(
            Button("Save") {
                 viewModel.saveFile()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!viewModel.isDirty || viewModel.fileURL == nil || !viewModel.isPlainText)
            .hidden() // Keep the button invisible
        )
        .navigationTitle(viewModel.fileURL?.lastPathComponent ?? "Buddy")
    }

    // Helper function to handle selection changes
    private func handleSelectionChange(item: FileSystemItem?) {
        guard let selectedFile = item, !selectedFile.isDirectory else {
            // If a directory is selected or selection is cleared, do nothing
            // (Keep showing the last file as per spec)
            return
        }
        
        // Load the new file
        viewModel.loadFile(url: selectedFile.url)
    }
}

// Placeholder Preview
#Preview {
    // Instantiate required ViewModels
    let folderVM = FolderViewModel()
    let contentVM = FileContentViewModel()
    // Optional: Set state on contentVM for different previews
    // contentVM.fileURL = URL(fileURLWithPath: "/dummy/file.txt")
    // contentVM.fileContent = "Sample file content\nAnother line."
    // contentVM.isPlainText = true
    
    FileContentView()
        .environmentObject(folderVM) // Provide FolderViewModel
        .environmentObject(contentVM) // Provide FileContentViewModel
        .frame(width: 400, height: 500)
} 