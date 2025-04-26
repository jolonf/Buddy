import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit // For NSWorkspace icon fetching
#endif

// Removed Dispatch import

// Removed Delegate Protocol

@MainActor
class FileContentViewModel: ObservableObject {
    
    // Removed Delegate Property
    
    // --- State Properties ---
    @Published var fileURL: URL? = nil
    @Published var fileContent: String = "" // Content for TextEditor
    @Published var originalContent: String = "" // For dirty checking
    @Published var isDirty: Bool = false
    @Published var isPlainText: Bool = true // Assume text initially
    @Published var fileIcon: Image? = nil
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false

    // Removed internalChangeOccurring flag

    // --- Removed File Monitoring State ---
    // private var fileMonitorSource: DispatchSourceFileSystemObject? = nil
    // private var fileDescriptor: Int32 = -1 

    init() {
        // Initialization logic to potentially observe FolderViewModel changes
        // will likely happen through an intermediary or direct observation
    }

    // Removed deinit
    
    // --- Actions ---
    func loadFile(url: URL) {
        print("Loading file: \(url.path)")
        isLoading = true
        errorMessage = nil
        
        // --- Removed monitoring stop call ---
        
        // Reset state before loading new file
        self.fileURL = nil // Set temporary fileURL first for error messages
        self.fileContent = ""
        self.originalContent = ""
        self.isDirty = false
        self.isPlainText = true
        self.fileIcon = nil
        
        // Defer setting loading to false to ensure it happens even on error
        defer { 
            isLoading = false 
            print("Finished loading attempt for: \(url.lastPathComponent)")
        }

        // Ensure we have security scope access to the file
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Permission denied to access file: \(url.lastPathComponent)"
            self.fileURL = url // Keep URL to show context of error
            return
        }
        // Release access when the function exits
        defer { url.stopAccessingSecurityScopedResource() }
        
        // Determine if text file
        if isTextFile(url: url) { 
            self.isPlainText = true
        } else {
             self.isPlainText = false
        }
        // Removed monitoring start call

        // Load initial content (text or icon)
        if self.isPlainText {
             // Use the reload function directly for initial load
             forceReloadFromDisk(url: url) 
        } else {
            // Handle non-text files (icon)
            self.fileURL = url // Store URL even for non-text
            self.fileContent = "" // Clear text content fields
            self.originalContent = ""
            self.isDirty = false
            
            // Fetch the icon (macOS only)
            #if os(macOS)
            let nsIcon = NSWorkspace.shared.icon(forFile: url.path)
            self.fileIcon = Image(nsImage: nsIcon)
            print("Loaded icon for non-text file.")
            #else
            // Placeholder for other platforms if needed
            self.fileIcon = Image(systemName: "doc")
            print("Non-text file detected (non-macOS fallback icon).")
            #endif
        }
    }

    // Renamed and made public function to reload content from disk
    public func forceReloadFromDisk(url providedUrl: URL? = nil) {
         // Use the ViewModel's current URL if none is provided
         guard let url = providedUrl ?? self.fileURL else {
             print("forceReloadFromDisk called but no URL is available.")
             return
         }
         
         // Don't reload if it's not a text file we are displaying
         guard self.isPlainText else { 
             print("forceReloadFromDisk called for non-plain-text file, ignoring.")
             return 
         }
         
         print("Force reloading content from disk for: \(url.lastPathComponent)")
         
         // Removed internalChangeOccurring check
         
         // Ensure we have security scope access to read
         guard url.startAccessingSecurityScopedResource() else {
             // Update error on MainActor (though this func is already MainActor)
             self.errorMessage = "Permission denied reloading file: \(url.lastPathComponent)"
             return
         }
         defer { url.stopAccessingSecurityScopedResource() }

         do {
             // Read the file content
             let content = try String(contentsOf: url, encoding: .utf8)
             // Update state on the main thread (already on MainActor)
             self.fileURL = url // Ensure URL is set if called with providedUrl
             self.fileContent = content
             // IMPORTANT: Reset originalContent as well when reloading from disk
             // This assumes the disk version is the new baseline.
             self.originalContent = content 
             self.isDirty = false // File matches disk, so not dirty
             self.errorMessage = nil // Clear previous errors on successful reload
             print("Successfully force-reloaded text file: \(url.lastPathComponent)")
         } catch {
             // Handle reading error
             self.errorMessage = "Failed to reload file: \(error.localizedDescription)"
             print("Error force-reloading text file: \(error.localizedDescription)")
         }
    }

    // --- Removed File Monitoring Logic ---
    // private func startMonitoring(url: URL) { ... }
    // private nonisolated func stopMonitoring(...) { ... }
    // --------------------------
    
    func saveFile() {
        // Removed delegate calls
        
        guard let url = fileURL, isDirty else {
            print("Save condition not met: URL=\(fileURL != nil), isDirty=\(isDirty)")
            return
        }
        
        print("Attempting to save file: \(url.path)")
        isLoading = true // Indicate saving activity
        errorMessage = nil
        
        // Removed monitoring stop/start logic and internalChangeOccurring flag
        
        defer { 
            isLoading = false 
        }

        // Ensure we have security scope access to write
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Permission denied to save file: \(url.lastPathComponent)"
            print("Save failed: Permission denied.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            // Removed internalChangeOccurring flag set
            // Write the current content to the file URL
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
            
            // Update state on successful save
            self.originalContent = self.fileContent // New baseline for dirty checking
            self.isDirty = false // Mark as no longer dirty
            print("File saved successfully.")
        } catch {
            // Removed internalChangeOccurring flag set
            // Handle writing error
            errorMessage = "Failed to save file: \(error.localizedDescription)"
            print("Save failed: \(error.localizedDescription)")
            // Do not change isDirty or originalContent on failure
        }
    }
    
    // --- Helpers ---
    func checkDirtyState() {
        // Compare fileContent with originalContent
         self.isDirty = fileContent != originalContent
    }
    
    func isTextFile(url: URL) -> Bool {
        // Check if the URL conforms to the public.text UTI
        do {
            let resourceValues = try url.resourceValues(forKeys: [.typeIdentifierKey])
            if let utiString = resourceValues.typeIdentifier, let uti = UTType(utiString) {
                // Check conformance to public.text or specific desired types
                return uti.conforms(to: .text) || uti.conforms(to: .plainText) || uti.conforms(to: .sourceCode)
            }
        } catch {
            print("Error getting UTI for \(url.lastPathComponent): \(error.localizedDescription)")
        }
        // Fallback or if UTI couldn't be determined
        return false
    }
} 