import SwiftUI
import Foundation
import Combine

// Revert to struct
struct CommandHistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let command: String
    var output: String = ""       // Regular property
    var exitCode: Int32? = nil    // Regular property
    // Initializer can be synthesized or kept explicit if needed

    // Equatable conformance based on ID (can be synthesized if struct is simple)
    // static func == (lhs: CommandHistoryEntry, rhs: CommandHistoryEntry) -> Bool {
    //     lhs.id == rhs.id
    // }
}

// Result structure for executed commands
struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

@MainActor
class CommandRunnerViewModel: ObservableObject {
    
    // --- State Properties ---
    @Published var commandInput: String = ""
    @Published var history: [CommandHistoryEntry] = [] // Array of structs
    @Published var isRunning: Bool = false
    // Remove outputAppendedTrigger
    // @Published var outputAppendedTrigger: Bool = false 
    
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
                Task { @MainActor [weak self] in 
                    guard let self = self else { return }
                    print("Process terminated with code: \(exitCode)")
                    // Find index and update struct by replacing it in the array
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
                    handle.readabilityHandler = nil
                } else if let outputChunk = String(data: data, encoding: .utf8) {
                    // <<< Add debug print here >>>
                    print("DEBUG: stdout received chunk: \(outputChunk.prefix(50).replacingOccurrences(of: "\n", with: "\\n"))[...]")
                    Task { @MainActor [weak self] in 
                        guard let self = self else { return }
                        // Find index and append to struct property (will require replacement)
                        if let index = self.history.firstIndex(where: { $0.id == entryID }) {
                            // Append directly (won't trigger UI update itself, but history modified)
                            self.history[index].output.append(outputChunk)
                        }
                    }
                }
            }

            stderrHandle?.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else if let errorOutput = String(data: data, encoding: .utf8) {
                     // <<< Add debug print here >>>
                     print("DEBUG: stderr received chunk: \(errorOutput.prefix(50).replacingOccurrences(of: "\n", with: "\\n"))[...]")
                     Task { @MainActor [weak self] in 
                        guard let self = self else { return }
                        // Find index and append to struct property (will require replacement)
                         if let index = self.history.firstIndex(where: { $0.id == entryID }) {
                            self.history[index].output.append("\n[STDERR]:\n" + errorOutput)
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
                    // Find index and update struct by replacing it in the array
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
        // Obsolete TODO removed
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
        // Obsolete TODO removed
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

    // --- New Helper for Agent Commands (Struct) ---
    @MainActor
    func addCompletedAgentCommandToHistory(command: String, result: CommandResult) {
        // Combine stdout and stderr
        var combinedOutput = result.stdout
        if !result.stderr.isEmpty {
            combinedOutput += "\n[STDERR]:\n" + result.stderr
        }
        
        // Create the entry STRUCT
        let entry = CommandHistoryEntry(
            command: command, 
            output: combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: result.exitCode
        )
        history.append(entry)
        
        // Optionally, add to the executable command history for up/down arrows
        if executedCommands.last != command {
            executedCommands.append(command)
        }
        print("Added agent command '\(command)' to UI history.")
    }

    // Make this nonisolated as Process is thread-safe and we do blocking work
    nonisolated func executeCommandForAgent(command: String, workingDirectory: URL) async -> CommandResult {
        print("Agent executing command: '\(command)' in directory: \(workingDirectory.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh") // Use zsh
        process.arguments = ["-c", command] // Execute original command string directly
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            // Read stdout synchronously AFTER process finishes
            let stdOutputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            // Read stderr synchronously AFTER process finishes
            let stdErrorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            process.waitUntilExit() // Wait for the process to finish

            let stdoutString = String(data: stdOutputData, encoding: .utf8) ?? "Error decoding stdout"
            let stderrString = String(data: stdErrorData, encoding: .utf8) ?? "Error decoding stderr"
            let exitCode = process.terminationStatus

            print("Agent command finished. Exit code: \(exitCode)")
            return CommandResult(stdout: stdoutString, stderr: stderrString, exitCode: exitCode)

        } catch {
            print("Failed to run agent command: \(error)")
            return CommandResult(stdout: "", stderr: "Failed to launch command: \(error.localizedDescription)", exitCode: -1)
        }
    }
} 