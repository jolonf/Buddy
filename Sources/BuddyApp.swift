import SwiftUI
#if os(macOS)
import AppKit // Needed for NSApplication
#endif

#if os(macOS)
// MARK: - AppDelegate
// Conforms to NSApplicationDelegate to handle app lifecycle events
class AppDelegate: NSObject, NSApplicationDelegate {
    // This method is called when the last window of the application is closed.
    // Returning true ensures the application terminates.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

@main
struct BuddyApp: App {
#if os(macOS)
    // Use the adaptor to connect our custom AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    // Create all ViewModels as StateObjects at the App level
    @StateObject private var folderViewModel: FolderViewModel
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var commandRunnerViewModel: CommandRunnerViewModel
    @StateObject private var fileContentViewModel: FileContentViewModel
    
    init() {
        // Create folderViewModel first
        let folderVM = FolderViewModel()
        _folderViewModel = StateObject(wrappedValue: folderVM)
        
        // Create fileContentViewModel explicitly
        let fileContentVM = FileContentViewModel()
        _fileContentViewModel = StateObject(wrappedValue: fileContentVM)
        
        // Create commandRunnerViewModel (no dependencies)
        let commandRunnerVM = CommandRunnerViewModel()
        _commandRunnerViewModel = StateObject(wrappedValue: commandRunnerVM)
        
        // Create RemoteChatService instance
        // TODO: Make server URL configurable later
        let remoteService = RemoteChatService(serverURL: "http://localhost:1234")
        let localService = LocalChatService()
        
        // Now create chatViewModel, passing folderVM, commandRunnerVM, and remoteService
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(folderViewModel: folderVM, commandRunnerViewModel: commandRunnerVM, remoteChatService: remoteService, localChatService: localService))

        // --- Connect ViewModels ---
        folderVM.setup(fileContentViewModel: fileContentVM)
        // --------------------------
        
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
        WindowGroup() {
            // Use NavigationSplitView for Sidebar + Content + Detail layout
            NavigationSplitView {
                FolderView()
            } content: {
#if os(macOS)
                // Use VSplitView for File Content and Command Runner
                VSplitView {
                    FileContentView()
                    CommandRunnerView()
                }
#else
                FileContentView()
#endif
            } detail: {
                ChatView()
                    // Reduced width constraints for the detail pane
                    .navigationSplitViewColumnWidth(min: 200, ideal: 300, max: 350)
            }
            // Inject all ViewModels into the environment
            .environmentObject(folderViewModel)
            .environmentObject(chatViewModel)
            .environmentObject(commandRunnerViewModel)
            .environmentObject(fileContentViewModel)
        }
    }
} 
