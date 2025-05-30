# Phase 4: Command Execution Panel

**1. Goal:**
   Allow users to execute shell commands within the context of the selected project folder and view the command history and output directly within the application.

**2. UI Changes:**
   *   **Modify `BuddyApp.swift` / Main Layout:**
        *   The main `content` pane (of the root `NavigationSplitView`) will contain a `VSplitView`.
        *   The top part of the `VSplitView` holds the `FileContentView`.
        *   The bottom part of the `VSplitView` holds the new `CommandRunnerView`.
   *   **Command Input (in `CommandRunnerView`):** Include a `TextField` for users to type shell commands. Add a "Run" button next to it.
   *   **Command Output (in `CommandRunnerView`):** Implement a scrollable view (`ScrollViewReader` wrapped around `ScrollView` + `LazyVStack` likely) to display an appending log of commands and their corresponding standard output (stdout) and standard error (stderr).
   *   **Running State (in `CommandRunnerView`):** The "Run" button should be disabled, and potentially the `TextField` too, while a command is executing. A "Stop" button should appear during execution.
   *   **Clear Button (in `CommandRunnerView`):** Add a "Clear Log" button, perhaps near the output area.

**3. Core Functionality:**
   *   **State Management:**
        *   Introduce a new `ObservableObject` class, tentatively `CommandRunnerViewModel`, responsible for:
            *   Current command input string.
            *   History of executed commands and their outputs (e.g., an array of structs (`CommandHistoryEntry`), each containing command string, output string, exit code, maybe timestamps).
            *   `isRunning` flag (Bool) to control UI state (enable/disable input, show Stop button).
            *   Reference to the process (`Process` object) currently running (if any).
        *   `CommandRunnerView` will observe and interact with this `CommandRunnerViewModel`.
   *   **Command Execution:**
        *   When the "Run" button is tapped (or TextField submitted):
            *   Ensure no other command is currently running (`isRunning == false`).
            *   Get the command string from the input `TextField`.
            *   Get the `selectedFolderURL` from `FolderViewModel` (via `EnvironmentObject`). Return/show error if no folder is selected.
            *   Set `isRunning = true`.
            *   Create and append a new `CommandHistoryEntry` to the history list for the command being run.
            *   Launch `/bin/zsh` (or `/bin/bash`) using the `Process` API.
                *   Set arguments to `["-c", enteredCommandString]`.
                *   Set `currentDirectoryURL` to the selected project folder URL.
                *   Set up `Pipe`s for stdout and stderr.
            *   Store the `Process` object.
            *   Asynchronously read data from the stdout/stderr pipes using `FileHandle`.
            *   Append received output data (converted to String, assuming UTF-8) to the `output` property of the corresponding `CommandHistoryEntry` in the history list.
            *   Set a termination handler for the `Process`.
   *   **Process Termination:**
        *   When the process finishes, the termination handler should:
            *   Capture the exit code.
            *   Update the `exitCode` property of the corresponding `CommandHistoryEntry`.
            *   Ensure all pipe reading is finished.
            *   Set `isRunning = false`.
            *   Clear the reference to the `Process` object.
   *   **Stopping Commands:**
        *   The "Stop" button (visible when `isRunning == true`) should call `process.terminate()` on the stored `Process` object. The termination handler should still execute to clean up state.
   *   **Clearing Log:**
        *   The "Clear Log" button will clear the command/output history array in the `CommandRunnerViewModel`.
   *   **Error Handling:**
        *   Errors during process launch (e.g., invalid path) or non-zero exit codes should be reflected in the `output` and `exitCode` properties of the relevant `CommandHistoryEntry`.
        *   Standard error (stderr) should also be appended to the `output` property, prefixed with `"[STDERR]:"`.

**4. Non-Functional Requirements:**
   *   Command output should appear relatively quickly as it's generated.
   *   The UI should remain responsive while commands are running.
   *   Resource cleanup (pipes, file handles, process object) must be handled correctly on termination or stop.

**5. Future Considerations / Out of Scope for Phase 4:**
   *   Full terminal emulation (colors, cursor positioning, interactive input *during* execution).
   *   Handling complex shell interactions (pipes `|`, redirection `>`, etc.) beyond what the `-c` flag provides simply.
   *   Running multiple commands concurrently.
   *   Parsing command strings into executable/arguments manually.
   *   ~~Visual distinction between stdout and stderr in the log.~~ (Basic distinction via `[STDERR]:` prefix implemented).