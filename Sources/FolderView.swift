import SwiftUI
import UniformTypeIdentifiers // Required for .folder

struct FolderView: View {
    // Use EnvironmentObject to receive the ViewModel from the ancestor
    @EnvironmentObject var viewModel: FolderViewModel

    var body: some View {
        VStack(alignment: .leading) { // Align content to leading edge
            // --- Top Controls/Info ---
            HStack {
                Text(viewModel.selectedFolderURL?.lastPathComponent ?? "No Folder Selected")
                    .font(.headline)
                    .truncationMode(.middle) // Truncate long names
                    .lineLimit(1)
                Spacer() // Pushes button to the right
                Button {
                    viewModel.selectFolder() // Trigger the file importer
                } label: {
                    Image(systemName: "folder.badge.plus") // More appropriate icon
                }
                .help("Select Project Folder")
            }
            .padding(.top, 5) // Reduced top padding slightly
            .padding(.horizontal)
            .padding(.bottom, 5)

            Divider()

            // --- Folder Contents / Error / Loading State ---
            if let error = viewModel.accessError {
                ContentUnavailableView {
                    Label("Error Accessing Folder", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(error)
                }
            } else if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Center the progress view
            } else if viewModel.selectedFolderURL == nil {
                 ContentUnavailableView {
                     Label("No Folder Selected", systemImage: "folder.badge.questionmark")
                 } description: {
                     Text("Select a project folder to view its contents.")
                 } actions: {
                     Button("Select Folder") { viewModel.selectFolder() }
                 }
            } else {
                // --- File List ---
                List(viewModel.rootFileSystemItems, children: \.children, selection: $viewModel.selectedItem) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                            .foregroundColor(item.isDirectory ? .blue : .secondary)
                        Text(item.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .tag(item)
                    .onAppear {
                        viewModel.loadChildrenIfNeeded(for: item)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteItem(item)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Button("Delete Selected Item") {
                if let selected = viewModel.selectedItem {
                    viewModel.deleteItem(selected)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .hidden()
        }
        .background(.regularMaterial)
        // Add the file importer modifier
        .fileImporter(
            isPresented: $viewModel.isShowingFileImporter,
            allowedContentTypes: [.folder] // Only allow folders
        ) { result in
            switch result {
            case .success(let url):
                // Call the ViewModel method to handle the selected URL
                viewModel.handleSelectedFolder(url: url)
            case .failure(let error):
                // Optionally handle the error directly here or let the ViewModel handle it
                print("File Importer Error: \(error.localizedDescription)")
                viewModel.accessError = "Failed to select folder: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    let dummyFolderVM = FolderViewModel()
    // Optional: Populate dummyFolderVM with sample data for preview states
    // dummyFolderVM.rootFileSystemItems = [
    //     FileSystemItem(name: "Folder 1", url: URL(fileURLWithPath: "/dummy/folder1"), isDirectory: true, children: nil),
    //     FileSystemItem(name: "File 1.txt", url: URL(fileURLWithPath: "/dummy/file1.txt"), isDirectory: false, children: nil)
    // ]
    // dummyFolderVM.selectedFolderURL = URL(fileURLWithPath: "/dummy")
    
    return FolderView()
        .environmentObject(dummyFolderVM)
        .frame(width: 250) // Give it a reasonable width for preview
}

 