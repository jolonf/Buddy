import SwiftUI
import Foundation

// Placeholder struct for command history entries
struct CommandHistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let command: String
    var output: String = ""
    var exitCode: Int32? = nil
    // Add timestamps, etc. later if needed
}

@MainActor
class CommandRunnerViewModel: ObservableObject {
    
    // --- State Properties ---
    @Published var commandInput: String = ""
    @Published var history: [CommandHistoryEntry] = []
    @Published var isRunning: Bool = false
    
    // --- Command History Navigation ---
    private var executedCommands: [String] = []
    private var historyNavigationIndex: Int? = nil
    private var currentInputBeforeHistory: String = ""

    // Reference to the running process
    private var currentProcess: Process?
    // FileHandles for reading pipes
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    
    init() {
        // Initialization
    }
    
    // --- Actions ---
    func runCommand(workingDirectory: URL) {
        guard !isRunning else {
            print("Command already running.")
            return
        }
        let commandToRun = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandToRun.isEmpty else {
            print("Command input is empty.")
            return
        }

        // Create history entry
        let newEntry = CommandHistoryEntry(command: commandToRun)
        let entryID = newEntry.id
        history.append(newEntry)
        // Only add unique consecutive commands to history
        if executedCommands.last != commandToRun {
            executedCommands.append(commandToRun)
        }
        commandInput = "" // Clear input field
        historyNavigationIndex = nil // Reset history navigation on new command
        isRunning = true

        Task {
            // Setup Process
            let task = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            task.executableURL = URL(fileURLWithPath: "/bin/zsh") // Or /bin/bash
            task.arguments = ["-c", commandToRun]
            task.currentDirectoryURL = workingDirectory
            task.standardOutput = outputPipe
            task.standardError = errorPipe

            self.stdoutHandle = outputPipe.fileHandleForReading
            self.stderrHandle = errorPipe.fileHandleForReading
            self.currentProcess = task

            // --- Termination Handler ---
            task.terminationHandler = { [weak self] process in
                let exitCode = process.terminationStatus
                Task { @MainActor [weak self] in // Dispatch back to main actor
                    guard let self = self else { return }
                    print("Process terminated with code: \(exitCode)")
                    if let index = self.history.firstIndex(where: { $0.id == entryID }) {
                        self.history[index].exitCode = exitCode
                    }
                    self.isRunning = false
                    self.currentProcess = nil
                    // Close pipes after process termination and potential final reads
                    try? self.stdoutHandle?.close()
                    try? self.stderrHandle?.close()
                    self.stdoutHandle = nil
                    self.stderrHandle = nil
                }
            }

            // --- Asynchronous Output Reading ---
            stdoutHandle?.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty {
                    // End of file, stop reading
                    handle.readabilityHandler = nil
                } else if let output = String(data: data, encoding: .utf8) {
                    Task { @MainActor [weak self] in // Dispatch back to main actor
                        guard let self = self else { return }
                        if let index = self.history.firstIndex(where: { $0.id == entryID }) {
                            self.history[index].output.append(output)
                            // TODO: Add logic to scroll output view?
                        }
                    }
                }
            }

            stderrHandle?.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else if let errorOutput = String(data: data, encoding: .utf8) {
                     Task { @MainActor [weak self] in // Dispatch back to main actor
                        guard let self = self else { return }
                         if let index = self.history.firstIndex(where: { $0.id == entryID }) {
                            self.history[index].output.append("\n[STDERR]:\n" + errorOutput) // Prepend stderr marker
                            // TODO: Add logic to scroll output view?
                        }
                    }
                }
            }

            // --- Launch Process ---
            do {
                try task.run()
                print("Launched process for: \(commandToRun)")
            } catch {
                // Handle launch errors
                Task { @MainActor [weak self] in // Dispatch back to main actor
                    guard let self = self else { return }
                    let errorMessage = "Failed to launch command: \(error.localizedDescription)"
                    if let index = self.history.firstIndex(where: { $0.id == entryID }) {
                        self.history[index].output.append(errorMessage)
                        self.history[index].exitCode = -1 // Indicate launch failure
                    }
                    self.isRunning = false
                    self.currentProcess = nil
                    print(errorMessage)
                }
            }
        }
    }
    
    func stopCommand() {
        // TODO: Implement process termination
        print("Placeholder: Stop current command")
        guard let process = currentProcess else {
            print("No process is currently running.")
            return
        }
        print("Terminating process...")
        process.terminate()
        // The termination handler will set isRunning to false, etc.
    }
    
    func clearLog() {
        // TODO: Implement log clearing
        print("Placeholder: Clear command log")
        history = []
        historyNavigationIndex = nil // Reset history navigation
    }
    
    // --- Helpers ---

    func navigateHistoryUp() {
        guard !executedCommands.isEmpty else { return }

        if historyNavigationIndex == nil {
            // Starting navigation, save current input
            currentInputBeforeHistory = commandInput
            historyNavigationIndex = executedCommands.count - 1
        } else if historyNavigationIndex! > 0 {
            // Navigate further up
            historyNavigationIndex! -= 1
        } else {
            // Already at the top
            return
        }

        // Update input field
        if let index = historyNavigationIndex {
            commandInput = executedCommands[index]
        }
    }

    func navigateHistoryDown() {
        guard let currentIndex = historyNavigationIndex else {
            // Not currently navigating history
            return
        }

        if currentIndex < executedCommands.count - 1 {
            // Navigate down
            historyNavigationIndex! += 1
            commandInput = executedCommands[historyNavigationIndex!]
        } else {
            // Reached the end, restore original input
            historyNavigationIndex = nil
            commandInput = currentInputBeforeHistory
        }
    }

    // TODO: Add helpers for appending output, handling termination
} 