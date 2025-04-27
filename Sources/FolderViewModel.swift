import Foundation
import SwiftUI // For AppStorage, ObservableObject
import UniformTypeIdentifiers // For UTType.folder

@MainActor // Ensure UI updates are on the main thread
class FolderViewModel: ObservableObject {
    
    // Reference to the FileContentViewModel
    private var fileContentViewModel: FileContentViewModel? = nil
    
    // --- Persisted State --- 
    // Store the secure bookmark data for the selected folder
    @AppStorage("selectedFolderBookmarkData") private var selectedFolderBookmarkData: Data?
    
    // --- Published State for UI ---
    @Published var selectedFolderURL: URL? = nil
    @Published var rootFileSystemItems: [FileSystemItem] = [] // Placeholder for file items
    @Published var accessError: String? = nil
    @Published var isLoading: Bool = false
    @Published var isShowingFileImporter: Bool = false // State for .fileImporter
    @Published var selectedItem: FileSystemItem? = nil // Added to track selection
    
    // --- File System Monitoring ---
    private var folderMonitorSource: DispatchSourceFileSystemObject?
    private var monitoredFolderDescriptor: CInt = -1 // File descriptor for monitored URL
    var urlToSelectAfterRefresh: URL? = nil // Store URL to select after monitor refreshes list (internal access)
    
    init() {
        resolveBookmarkAndStartAccess() 
    }
    
    // Method to connect the ViewModels
    func setup(fileContentViewModel: FileContentViewModel) {
        self.fileContentViewModel = fileContentViewModel
    }
    
    // --- Actions ---
    
    // Called by the View's Button
    func selectFolder() {
        isShowingFileImporter = true
    }
    
    // Called by the View's .fileImporter completion handler
    func handleSelectedFolder(url: URL) {
        stopAccessingCurrentBookmark()
        
        guard let bookmarkData = generateBookmark(for: url) else { 
            accessError = "Could not create security bookmark for the selected folder."
            selectedFolderURL = nil
            return 
        }
        
        selectedFolderBookmarkData = bookmarkData
        
        resolveBookmarkAndStartAccess()
    }
    
    // --- Bookmark Handling ---
    
    private func generateBookmark(for url: URL) -> Data? {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                accessError = "Permission denied before bookmark creation."
                return nil
            }
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            url.stopAccessingSecurityScopedResource()
            return bookmarkData
        } catch {
            accessError = "Failed to create bookmark: \(error.localizedDescription)"
            url.stopAccessingSecurityScopedResource()
            return nil
        }
    }
    
    private func resolveBookmarkAndStartAccess() {
        guard let bookmarkData = selectedFolderBookmarkData else {
            selectedFolderURL = nil
            rootFileSystemItems = []
            return
        }
        
        do {
            var isStale = false
            let resolvedUrl = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                guard let newBookmarkData = generateBookmark(for: resolvedUrl) else {
                    accessError = "The saved folder location is no longer valid and could not be updated."
                    selectedFolderBookmarkData = nil
                    selectedFolderURL = nil
                    rootFileSystemItems = []
                    return
                }
                selectedFolderBookmarkData = newBookmarkData
            }
            
            guard resolvedUrl.startAccessingSecurityScopedResource() else {
                accessError = "Permission denied when trying to access the saved folder."
                selectedFolderURL = nil
                rootFileSystemItems = []
                selectedFolderBookmarkData = nil
                return
            }
            
            self.selectedFolderURL = resolvedUrl
            self.accessError = nil
            
            startMonitoring(url: resolvedUrl)
            
            loadFolderContents(from: resolvedUrl)
            
        } catch {
            if error.localizedDescription.contains("correct format") || 
               error.localizedDescription.contains("bookmark data is corrupted") {
                accessError = "Saved folder data was corrupted or invalid. Please select the folder again."
                selectedFolderBookmarkData = nil
            } else {
                accessError = "Could not access saved folder: \(error.localizedDescription)" 
                selectedFolderBookmarkData = nil 
            }
            selectedFolderURL = nil
            rootFileSystemItems = []
        }
    }
    
    private func stopAccessingCurrentBookmark() {
        stopMonitoring()
        
        guard let url = selectedFolderURL else { return }
        url.stopAccessingSecurityScopedResource()
        selectedFolderURL = nil
        rootFileSystemItems = []
    }
    
    // --- File System Loading ---
    
    private func loadFolderContents(from url: URL) {
        isLoading = true
        accessError = nil
        // Don't clear rootFileSystemItems immediately
        // rootFileSystemItems = [] 

        guard url.startAccessingSecurityScopedResource() else {
            // ... error handling ...
            // Ensure we clear items if access fails here
            self.rootFileSystemItems = []
            return
        }
        
        defer {
            isLoading = false
            // Stop access ONLY if we are NOT monitoring this URL
            // If monitoring is active, keep access
            if folderMonitorSource == nil || self.selectedFolderURL != url {
                 url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            // 1. Get current items on disk
            let diskUrls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .nameKey], options: .skipsHiddenFiles)
            
            // 2. Map existing items by URL for quick lookup
            var existingItemsMap = Dictionary(uniqueKeysWithValues: rootFileSystemItems.map { ($0.url, $0) })
            
            var updatedItems: [FileSystemItem] = []

            // 3. Process items currently on disk
            for diskUrl in diskUrls {
                let resourceValues = try diskUrl.resourceValues(forKeys: [.nameKey, .isDirectoryKey])
                let name = resourceValues.name ?? diskUrl.lastPathComponent
                let isDirectory = resourceValues.isDirectory ?? false

                if let existingItem = existingItemsMap[diskUrl] {
                    // Item exists, reuse it (preserves ID and children)
                    // Optional: Update properties if they can change, e.g., name
                    // if existingItem.name != name { existingItem.name = name } // Requires FileSystemItem.name to be var
                    updatedItems.append(existingItem)
                    existingItemsMap.removeValue(forKey: diskUrl) // Mark as processed
                } else {
                    // New item found on disk
                    let newItem = FileSystemItem(name: name, url: diskUrl, isDirectory: isDirectory, children: isDirectory ? nil : nil)
                    updatedItems.append(newItem)
                }
            }
            
            // Items remaining in existingItemsMap were deleted from disk - they are implicitly removed
            // by not being added to updatedItems.

            // 5. Sort and update the main array
            self.rootFileSystemItems = updatedItems.sorted { (item1, item2) -> Bool in
                if item1.isDirectory != item2.isDirectory {
                    return item1.isDirectory
                }
                return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
            }
            
        } catch {
            accessError = "Failed to load folder contents: \(error.localizedDescription)"
            // On error, clear the list to avoid showing stale/incorrect data
            self.rootFileSystemItems = [] 
        }
    }
    
    // Add this new function
    func loadChildrenIfNeeded(for item: FileSystemItem) {
        guard item.isDirectory else {
            return
        }
        
        guard item.url.startAccessingSecurityScopedResource() else {
            return
        }
        defer { item.url.stopAccessingSecurityScopedResource() }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: item.url,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: .skipsHiddenFiles
            )

            var loadedChildren: [FileSystemItem] = []
            for childUrl in contents {
                let resourceValues = try childUrl.resourceValues(forKeys: [.nameKey, .isDirectoryKey])
                let name = resourceValues.name ?? childUrl.lastPathComponent
                let isDirectory = resourceValues.isDirectory ?? false
                // Recursively set children to nil initially
                loadedChildren.append(FileSystemItem(name: name, url: childUrl, isDirectory: isDirectory, children: isDirectory ? nil : nil))
            }

            // Sort the loaded children
            let sortedChildren = loadedChildren.sorted { (item1, item2) -> Bool in
                if item1.isDirectory != item2.isDirectory {
                    return item1.isDirectory
                }
                return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
            }

            updateItemChildren(itemId: item.id, newChildren: sortedChildren)

        } catch {
             updateItemChildren(itemId: item.id, newChildren: [])
        }
    }

    // Helper function to recursively find and update item's children
    private func updateItemChildren(itemId: UUID, newChildren: [FileSystemItem]) {
        func findAndUpdate(items: inout [FileSystemItem]) -> Bool {
            for i in items.indices {
                if items[i].id == itemId {
                    items[i].children = newChildren
                    return true
                }
                if items[i].isDirectory, items[i].children != nil {
                     if findAndUpdate(items: &items[i].children!) {
                         return true
                     }
                }
            }
            return false
        }

        if findAndUpdate(items: &rootFileSystemItems) {
            // Item found and updated (do nothing extra)
        } else {
            // Item not found (shouldn't happen if called correctly)
            // print("Warning: Could not find item with ID \(itemId) to update children.") // Example logging
        }
    }

    // Helper to find an item by URL recursively
    private func findItem(for url: URL, in items: [FileSystemItem]) -> FileSystemItem? {
        for item in items {
            if item.url == url {
                return item
            }
            // Check children only if they exist (have been loaded)
            if let children = item.children {
                if let foundInChildren = findItem(for: url, in: children) {
                    return foundInChildren
                }
            }
        }
        return nil
    }

    // Public method to select a file by its URL
    public func selectFile(url: URL) {
        print("Attempting to select file programmatically: \(url.path)")
        // Search for the item corresponding to the URL in the current items
        if let itemToSelect = findItem(for: url, in: rootFileSystemItems) {
            // Check if it's already selected to avoid redundant updates
            if self.selectedItem?.id != itemToSelect.id {
                print("Found matching item: \(itemToSelect.name). Setting as selectedItem.")
                self.selectedItem = itemToSelect
            } else {
                print("Item \(itemToSelect.name) is already selected.")
            }
        } else {
            // This might happen if the folder contents haven't refreshed yet after a new file creation.
            // Or if the file is in a subdirectory whose children haven't been loaded yet.
            print("Could not find FileSystemItem for URL: \(url.path) in current root list or loaded children.")
            // TODO: Potentially trigger lazy loading of parent directory children if needed?
        }
    }

    // --- File Deletion ---
    func deleteItem(_ item: FileSystemItem) {
        print("Attempting to delete item: \(item.url.path)")
        
        // Basic confirmation (can be enhanced later)
        // Note: Alerts should ideally be handled in the View layer
        // For now, just print confirmation request.
        print("Confirmation required to delete \(item.name)")
        // guard confirmDeletion() else { return } // Placeholder for future UI confirmation

        // Ensure we have scope access (needed for deletion too)
        guard let folderUrl = selectedFolderURL, folderUrl.startAccessingSecurityScopedResource() else {
            accessError = "Permission error before deleting \(item.name)"
             // Attempt to stop access if we failed to start it for the delete?
            selectedFolderURL?.stopAccessingSecurityScopedResource() 
            return
        }
        // Important: We need access to the PARENT directory containing the item to delete it.
        // The scope we have is for selectedFolderURL.
        // We also need to ensure the item URL itself is covered by this scope.
        guard item.url.path.starts(with: folderUrl.path) else {
             accessError = "Security Error: Attempt to delete item outside the selected folder scope."
             folderUrl.stopAccessingSecurityScopedResource()
             return
        }

        // Perform deletion
        do {
            try FileManager.default.removeItem(at: item.url)
            print("Successfully deleted \(item.name)")
            
            // Refresh folder contents to reflect deletion
            // Note: The directory monitor should also pick this up, 
            // but calling it directly ensures faster UI update.
            loadFolderContents(from: folderUrl)
            
            // Clear selection if the deleted item was selected
            // if selectedItem?.id == item.id {
            //     selectedItem = nil
            // } 
            // ^^^ Removed: Monitor handler will now handle clearing selection
            
        } catch {
            print("Error deleting item \(item.name): \(error)")
            accessError = "Failed to delete \(item.name): \(error.localizedDescription)"
        }
        
        // Stop access started for deletion
        folderUrl.stopAccessingSecurityScopedResource()
    }

    // MARK: - File System Monitoring Implementation

    private func stopMonitoring() {
        if folderMonitorSource != nil {
            folderMonitorSource?.cancel()
            folderMonitorSource = nil
        }
        if monitoredFolderDescriptor != -1 {
            close(monitoredFolderDescriptor)
            monitoredFolderDescriptor = -1
        }
    }

    private func startMonitoring(url: URL) {
        stopMonitoring()
        
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor != -1 else {
            return
        }
        self.monitoredFolderDescriptor = descriptor
        
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, 
                                                               eventMask: [.write, .delete, .rename, .extend],
                                                               queue: DispatchQueue.main)
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }

            // Keep existing logic to check access and reload folder
            guard let currentUrl = self.selectedFolderURL else {
                self.accessError = "Monitoring event triggered but no folder selected."
                self.stopAccessingCurrentBookmark()
                return
            }
            
            guard currentUrl.startAccessingSecurityScopedResource() else {
                self.accessError = "Permission to access the folder was lost. Please select it again."
                self.stopAccessingCurrentBookmark()
                return
            }
            defer { currentUrl.stopAccessingSecurityScopedResource() } // Ensure access is stopped after handling

            // Reload the folder contents (updates the sidebar)
            self.loadFolderContents(from: currentUrl)
            
            // --- Post-Reload Actions ---
            if let contentVM = self.fileContentViewModel, let previouslyDisplayedURL = contentVM.fileURL {
                if findItem(for: previouslyDisplayedURL, in: self.rootFileSystemItems) != nil {
                    if contentVM.isPlainText {
                        print("Folder change detected, triggering reload for existing displayed file: \(previouslyDisplayedURL.lastPathComponent)")
                        contentVM.forceReloadFromDisk()
                    }
                } else {
                    print("Displayed file \(previouslyDisplayedURL.lastPathComponent) was deleted. Clearing selection and display.")
                    self.selectedItem = nil 
                    contentVM.clearDisplay()
                }
            }
            
            // Check if we need to select a specific file (e.g., after agent EDIT_FILE)
            if let urlToSelect = self.urlToSelectAfterRefresh {
                print("Post-refresh: Attempting to select pending URL: \(urlToSelect.path)")
                self.selectFile(url: urlToSelect) // Select file using the *updated* list
                self.urlToSelectAfterRefresh = nil // Reset the pending selection
            }
            // --------------------------
        }
        
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.monitoredFolderDescriptor != -1 {
                close(self.monitoredFolderDescriptor)
                self.monitoredFolderDescriptor = -1
            }
        }
        
        self.folderMonitorSource = source
        source.resume()
    }
}

// MARK: - File System Item Structure

struct FileSystemItem: Identifiable, Hashable { // Added Hashable
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileSystemItem]? = nil // Added for hierarchy

    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        lhs.id == rhs.id
    }
} 