import Foundation
import SwiftUI // For AppStorage, ObservableObject
import UniformTypeIdentifiers // For UTType.folder

@MainActor // Ensure UI updates are on the main thread
class FolderViewModel: ObservableObject {
    
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
    
    init() {
        // TODO: Load persisted bookmark on init
        // TODO: Resolve URL from bookmark
        // TODO: Start security scope access
        // TODO: Load initial folder contents
        resolveBookmarkAndStartAccess() 
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
        
        if item.children != nil {
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
        } else {
        }
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

            guard let currentUrl = self.selectedFolderURL else {
                return
            }
            
            if currentUrl.startAccessingSecurityScopedResource() {
                self.loadFolderContents(from: currentUrl)
            } else {
                self.accessError = "Permission to access the folder was lost. Please select it again."
                self.stopAccessingCurrentBookmark()
            }
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