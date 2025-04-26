# Phase 5: LLM File System Actions

**1. Goal:**
   Enable the LLM integrated into the `ChatView` to interact with the project filesystem. This includes reading files, listing directories, and automatically editing files based on text commands embedded in the LLM's responses, but only when the application is in "Agent" mode. The LLM must report the details of any successful file edits back to the user.

**2. UI Changes:**
   *   **`ChatView`:**
        *   Remains the primary user interface for interacting with the LLM.
        *   Will display LLM responses, including potential reports of file edits.
   *   **Mode Toggle:**
        *   Implement a UI control (e.g., a Toggle, Segmented Control) associated with the `ChatView` or its container.
        *   Allows the user to switch between "Agent" mode (LLM actions enabled) and "Ask" mode (LLM actions disabled).
   *   **Confirmation UI:**
        *   No explicit UI confirmation is required for file edits. Edits requested by the LLM in Agent mode are performed automatically.

**3. Core Functionality:**
   *   **State Management (`ChatViewModel`):**
        *   Maintain the current `Interaction Mode` (`.agent` or `.ask`).
        *   Based on the mode, select and inject the appropriate system prompt into the context sent to the LLM.
   *   **System Prompts:**
        *   Store system prompt text in external files (e.g., `Resources/system_prompt_agent.txt`, `Resources/system_prompt_ask.txt`) read by the `ChatViewModel`.
        *   **Agent Prompt:** Instructs the LLM on how to use `ACTION:` commands (`READ_FILE`, `LIST_DIR`, `EDIT_FILE`), the multi-line `EDIT_FILE` format, the automatic nature of edits, and the requirement to report successful edits based on the provided `DIFF`.
        *   **Ask Prompt:** Explicitly states that actions are disabled and the LLM should focus on informational responses.
   *   **Action Parsing (`ChatViewModel`):**
        *   Scan incoming LLM response text for lines matching the pattern `ACTION: <ACTION_NAME>(<parameters>)`.
        *   Use robust parsing (e.g., regex) to extract action name and key-value parameters.
        *   For `EDIT_FILE`, detect and extract the multi-line content block defined by `CONTENT_START` and `CONTENT_END` markers.
   *   **Action Execution:**
        *   If in "Agent" mode and an `ACTION:` is detected:
            *   Delegate execution to appropriate services/ViewModels (potentially shared utilities for file I/O).
            *   `READ_FILE(path)`: Reads file content.
            *   `LIST_DIR(path)`: Lists directory contents.
            *   `EDIT_FILE(path, content)`:
                1.  Reads the original content of the file at `path`.
                2.  Attempts to write the new `content` provided by the LLM.
                3.  On success: Calculates a diff (e.g., unified format) between original and new content. Returns `SUCCESS` status and the `diff`.
                4.  On failure: Returns `ERROR` status and an error message.
   *   **Feedback Loop:**
        *   Action results (success/failure status, content/listing, or diff) are received by `ChatViewModel`.
        *   Format results into `ACTION_RESULT:` strings (see section 4).
        *   Store the formatted `ACTION_RESULT:` string.
        *   Prepend this `ACTION_RESULT:` string to the context of the *next* message sent to the LLM.
        *   Raw action results (file content, listings, diffs) are *not* displayed directly as chat messages to the user. The LLM uses the `ACTION_RESULT` to formulate its response, including the mandatory edit report.

**4. Action & Result Formats:**

   *   **LLM Action Request Format:**
        *   `ACTION: READ_FILE(path='path/to/file')`
        *   `ACTION: LIST_DIR(path='path/to/directory')`
        *   `ACTION: EDIT_FILE(path='path/to/file')`
        *   `CONTENT_START`
        *   `<new file content line 1>`
        *   `<new file content line 2>`
        *   `...`
        *   `CONTENT_END`

   *   **Action Result Format (Sent back to LLM):**
        *   Read Success:
            ```
            ACTION_RESULT: READ_FILE(path='...')
            STATUS: SUCCESS
            CONTENT_START
            <file_content>
            CONTENT_END
            ```
        *   List Success:
            ```
            ACTION_RESULT: LIST_DIR(path='...')
            STATUS: SUCCESS
            CONTENT_START
            <directory listing>
            CONTENT_END
            ```
        *   Edit Success:
            ```
            ACTION_RESULT: EDIT_FILE(path='...')
            STATUS: SUCCESS
            DIFF_START
            <unified diff format showing changes>
            DIFF_END
            ```
        *   Any Action Failure:
            ```
            ACTION_RESULT: <ACTION_NAME>(...)
            STATUS: ERROR: <error message>
            ```

**5. Non-Functional Requirements:**
   *   Action parsing should be robust against minor variations in parameter formatting if feasible.
   *   File I/O operations should handle potential errors gracefully (permissions, file not found, etc.) and report them back to the LLM.
   *   Diff generation should use a standard, easily understandable format (like unified diff).

**6. Future Considerations / Out of Scope for Phase 5:**
   *   LLM directly running shell commands.
   *   Handling extremely large file contents or directory listings (truncation, streaming).
   *   More complex action parameter types or structures.
   *   Advanced error recovery or clarification dialogues with the LLM.
   *   Visual diff display in the UI.
   *   User undo functionality for LLM edits. 