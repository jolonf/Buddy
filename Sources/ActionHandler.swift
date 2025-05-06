import Foundation

// ParsedAction struct is defined in ChatMessage.swift

// TODO: Move String.parseAsAction() extension here later if possible.

@MainActor // Ensure methods interacting with ViewModels are on main thread if needed
class ActionHandler {

    private let folderViewModel: FolderViewModel
    #if os(macOS)
    private let commandRunnerViewModel: CommandRunnerViewModel
    #endif

    // Define a callback closure type to send results back to ChatViewModel
    typealias ActionResultCallback = (String, Int) async -> Void // Added index
    private var sendResultCallback: ActionResultCallback?

    init(folderViewModel: FolderViewModel, commandRunnerViewModel: CommandRunnerViewModel) {
        self.folderViewModel = folderViewModel
        self.commandRunnerViewModel = commandRunnerViewModel
    }

    // Method for ChatViewModel to register its callback
    func registerSendResultCallback(_ callback: @escaping ActionResultCallback) {
        self.sendResultCallback = callback
    }

    // --- Methods moved from ChatViewModel ---

    // Make this public so ChatViewModel can call it
    public func parseAndExecuteActions(responseContent: String, originalMessageIndex: Int) async {
        print("--- Parsing Actions (Agent Mode) ---")
        var actionFoundAndExecuted = false // Track if we need to send result
        var actionResultString = ""       // Store result if found

        // Action parsing loop (now uncommented)
        let lines = responseContent.split(whereSeparator: \.isNewline)
        var i = 0
        while i < lines.count {
            let line = String(lines[i]) // Use full line string
            
            // Try parsing the line as an action
            if let parsedActionLine = line.parseAsAction() { 
                
                var multiLineContent: String? = nil
                var finalParsedAction = parsedActionLine // Start with parsed line
                
                // Handle multi-line content specifically for EDIT_FILE
                if parsedActionLine.name == "EDIT_FILE" {
                    var contentLines: [String] = []
                    var foundStart = false
                    var j = i + 1
                    while j < lines.count {
                        let contentLine = String(lines[j])
                        if contentLine.trimmingCharacters(in: .whitespaces) == "CONTENT_START" {
                            foundStart = true
                        } else if contentLine.trimmingCharacters(in: .whitespaces) == "CONTENT_END" {
                            if foundStart {
                                multiLineContent = contentLines.joined(separator: "\n")
                                i = j // Advance main loop past the content block
                                break
                            }
                        } else if foundStart {
                            contentLines.append(contentLine)
                        }
                        j += 1
                    }
                    if multiLineContent == nil {
                        print("Warning: EDIT_FILE action found but CONTENT_START/CONTENT_END markers were missing or malformed.")
                    }
                    finalParsedAction = ParsedAction(name: parsedActionLine.name, 
                                                   parameters: parsedActionLine.parameters, 
                                                   multiLineContent: multiLineContent)
                }

                print("Parsed Action: \(finalParsedAction.name), Params: \(finalParsedAction.parameters)")
                if let content = finalParsedAction.multiLineContent {
                    print("  Multi-line Content:")
                    print("---")
                    print("\(content)")
                    print("---")
                }
                
                actionResultString = await execute(action: finalParsedAction)
                actionFoundAndExecuted = true
                break // Assume one action per response
            }
            i += 1
        }
        
        print("--- Finished Parsing. Action found: \(actionFoundAndExecuted) ---")

        // If an action was found and executed, use the callback
        if actionFoundAndExecuted, let callback = sendResultCallback {
            // Pass result and original index back
            await callback(actionResultString, originalMessageIndex)
        } else if actionFoundAndExecuted {
            print("Error: Action executed but sendResultCallback is not registered.")
        }
    }
    
    // Keep private
    private func execute(action: ParsedAction) async -> String {
        print("Executing action '\(action.name)'...")
        
        guard let workingDirectoryURL = folderViewModel.selectedFolderURL else {
            return formatErrorResult(action: action, message: "No folder selected in the sidebar.")
        }
        
        let fileManager = FileManager.default
        let resultString: String

        switch action.name {
        case "READ_FILE":
            guard let relativePath = action.parameters["path"], !relativePath.isEmpty else {
                return formatErrorResult(action: action, message: "Missing or empty 'path' parameter for READ_FILE.")
            }
            let fileURL = workingDirectoryURL.appendingPathComponent(relativePath)
            do {
                guard fileURL.path.starts(with: workingDirectoryURL.path) else {
                    return formatErrorResult(action: action, message: "Access denied: Path is outside the selected folder.")
                }
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                resultString = """
                ACTION_RESULT: READ_FILE(path='\(relativePath)')
                STATUS: SUCCESS
                CONTENT:
                \(content)
                """
            } catch {
                resultString = formatErrorResult(action: action, message: "Failed to read file: \(error.localizedDescription)")
            }

        case "LIST_DIR":
            let relativePath = action.parameters["path"] ?? "."
            let dirURL = workingDirectoryURL.appendingPathComponent(relativePath)
            do {
                guard dirURL.path.starts(with: workingDirectoryURL.path) else {
                    return formatErrorResult(action: action, message: "Access denied: Path is outside the selected folder.")
                }
                let items = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                var listing = ""
                for itemURL in items {
                    var itemName = itemURL.lastPathComponent
                    if let isDirectory = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory == true {
                        itemName += "/"
                    }
                    listing += itemName + "\n"
                }
                resultString = """
                ACTION_RESULT: LIST_DIR(path='\(relativePath)')
                STATUS: SUCCESS
                LISTING:
                \(listing.trimmingCharacters(in: .newlines))
                """
            } catch {
                resultString = formatErrorResult(action: action, message: "Failed to list directory: \(error.localizedDescription)")
            }

        case "EDIT_FILE":
            guard let relativePath = action.parameters["path"], !relativePath.isEmpty else {
                return formatErrorResult(action: action, message: "Missing or empty 'path' parameter for EDIT_FILE.")
            }
            guard let newContent = action.multiLineContent else {
                return formatErrorResult(action: action, message: "Missing content block (CONTENT_START/END) for EDIT_FILE.")
            }
            let fileURL = workingDirectoryURL.appendingPathComponent(relativePath)
            
            do {
                guard fileURL.path.starts(with: workingDirectoryURL.path) else {
                    return formatErrorResult(action: action, message: "Access denied: Path is outside the selected folder.")
                }
                
                try newContent.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
                
                resultString = """
                ACTION_RESULT: EDIT_FILE(path='\(relativePath)')
                STATUS: SUCCESS
                """
                
                folderViewModel.urlToSelectAfterRefresh = fileURL

            } catch {
                 resultString = formatErrorResult(action: action, message: "Failed to write file: \(error.localizedDescription)")
            }

        case "RUN_COMMAND":
            guard let commandString = action.parameters["command"], !commandString.isEmpty else {
                return formatErrorResult(action: action, message: "Missing or empty 'command' parameter for RUN_COMMAND.")
            }
            let commandResult = await commandRunnerViewModel.executeCommandForAgent(
                command: commandString, 
                workingDirectory: workingDirectoryURL
            )
            resultString = """
            ACTION_RESULT: RUN_COMMAND(command='\(commandString)')
            EXIT_CODE: \(commandResult.exitCode)
            STDOUT_START
            \(commandResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            STDOUT_END
            STDERR_START
            \(commandResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            STDERR_END
            """

            commandRunnerViewModel.addCompletedAgentCommandToHistory(command: commandString, result: commandResult)

        default:
             resultString = formatErrorResult(action: action, message: "Unknown action name \'\(action.name)\'.")
        }

        print("Action Result:")
        print(resultString)
        return resultString
    }
    
    // Keep private
    private func formatErrorResult(action: ParsedAction, message: String) -> String {
        let paramsString = action.parameters.map { "\($0.key)='\($0.value)'" }.joined(separator: ", ")
        let originalAction = "\(action.name)(\(paramsString))"
        return """
        ACTION_RESULT: \(originalAction)
        STATUS: ERROR: \(message)
        """
    }

}

// MARK: - Action Parsing Extension
extension String {
    /// Attempts to parse the string as an ACTION command.
    /// Returns nil if the string doesn't match the expected format.
    func parseAsAction() -> ParsedAction? {
        let trimmedString = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedString.hasPrefix("ACTION:") else { return nil }

        let actionString = String(trimmedString.dropFirst("ACTION:".count)).trimmingCharacters(in: .whitespaces)

        // Basic parsing - assumes format ACTION_NAME(key='value',key2='value')
        // TODO: Make parsing more robust (e.g., regex)
        guard let openParen = actionString.firstIndex(of: "("),
              let closeParen = actionString.lastIndex(of: ")"),
              openParen < closeParen else { return nil }

        let actionName = String(actionString[..<openParen]).trimmingCharacters(in: .whitespaces)
        let paramsString = String(actionString[actionString.index(after: openParen)..<closeParen])

        var parameters: [String: String] = [:]
        let paramPairs = paramsString.split(separator: ",") // Adjust split if needed
        for pair in paramPairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                // Trim whitespace and potential quotes (' or ")
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\'\""))
                parameters[key] = value
            }
        }
        
        // Note: Multi-line content parsing is handled separately here in ActionHandler 
        // This parser only handles the ACTION: line itself.
        return ParsedAction(name: actionName, parameters: parameters, multiLineContent: nil)
    }
} 
