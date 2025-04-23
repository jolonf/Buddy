import SwiftUI
#if os(macOS)
import AppKit // Needed for NSApplication
#endif

// MARK: - AppDelegate
// Conforms to NSApplicationDelegate to handle app lifecycle events
class AppDelegate: NSObject, NSApplicationDelegate {
    // This method is called when the last window of the application is closed.
    // Returning true ensures the application terminates.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct BuddyApp: App {
    
    // Use the adaptor to connect our custom AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Create the FolderViewModel here as a StateObject
    @StateObject private var folderViewModel = FolderViewModel()
    
    init() {
        #if os(macOS)
        // Ensure the app behaves like a standard GUI app on macOS
        // even when built as a command-line executable.
        NSApplication.shared.setActivationPolicy(.regular)
        
        // Activate asynchronously to ensure the main run loop has started.
        DispatchQueue.main.async {
             NSApplication.shared.activate(ignoringOtherApps: true)
        }
        #endif
    }
     
    var body: some Scene {
        WindowGroup {
            // Use NavigationSplitView for Sidebar + Content + Detail layout
            NavigationSplitView {
                // Sidebar View
                FolderView()
            } content: {
                // Content View (Placeholder - could show file content later)
                Text(folderViewModel.selectedItem?.name ?? "Select an item")
                    .foregroundColor(.secondary)
            } detail: {
                // Detail View (Primary interaction area)
                ChatView()
            }
            // Inject the FolderViewModel into the environment
            .environmentObject(folderViewModel)
        }
    }
} 