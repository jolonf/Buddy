import SwiftUI
#if os(macOS)
import AppKit // Needed for NSApplication
#endif

@main
struct BuddyApp: App {
    
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
            ContentView()
        }
    }
} 