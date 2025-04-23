import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit // For NSWorkspace icon fetching
#endif

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

    init() {
        // Initialization logic to potentially observe FolderViewModel changes
        // will likely happen through an intermediary or direct observation
    }
    
    // --- Actions ---
    func loadFile(url: URL) {
        print("Loading file: \(url.path)")
        isLoading = true
        errorMessage = nil
        // Reset state before loading new file
        self.fileURL = nil
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
            return
        }
        // Release access when the function exits
        defer { url.stopAccessingSecurityScopedResource() }

        // Check if it's a text file using our helper
        if isTextFile(url: url) {
            self.isPlainText = true
            do {
                // Read the file content
                let content = try String(contentsOf: url, encoding: .utf8)
                // Update state on success
                self.fileURL = url
                self.fileContent = content
                self.originalContent = content // Store original for comparison
                self.isDirty = false
                print("Successfully loaded text file.")
            } catch {
                // Handle reading error
                errorMessage = "Failed to read file: \(error.localizedDescription)"
                 // Clear potentially partially set state
                self.fileURL = url // Keep URL to show which file failed
                self.fileContent = ""
                self.originalContent = ""
                self.isDirty = false
                self.isPlainText = true // Assume it might have been text
                print("Error reading text file: \(error.localizedDescription)")
            }
        } else {
            // Handle non-text files
            self.isPlainText = false
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
    
    func saveFile() {
        // Removed delegate calls
        
        guard let url = fileURL, isDirty else {
            print("Save condition not met: URL=\(fileURL != nil), isDirty=\(isDirty)")
            return
        }
        
        print("Attempting to save file: \(url.path)")
        isLoading = true // Indicate saving activity
        errorMessage = nil
        
        defer { isLoading = false } // Ensure loading indicator stops

        // Ensure we have security scope access to write
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Permission denied to save file: \(url.lastPathComponent)"
            print("Save failed: Permission denied.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            // Write the current content to the file URL
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
            
            // Update state on successful save
            self.originalContent = self.fileContent // New baseline for dirty checking
            self.isDirty = false // Mark as no longer dirty
            print("File saved successfully.")
        } catch {
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