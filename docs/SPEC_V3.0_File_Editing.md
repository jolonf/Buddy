# Phase 3: File Content Display and Editing

**1. Goal:**
   Enable users to view and edit the content of text files selected in the `FolderView` sidebar. Provide appropriate feedback for non-text files, unsaved changes, and errors.

**2. UI Changes:**
   *   **`FileContentView.swift`:** Create a new SwiftUI View for the `content` pane of the `NavigationSplitView`.
   *   **Content Display:**
        *   If the selected item is a text file, `FileContentView` will primarily display a `TextEditor` bound to the file's content.
        *   If the selected item is a non-text file, `FileContentView` will display the file's icon (e.g., fetched via `NSWorkspace.shared.icon(forFile:)`) centered in the view.
        *   If a directory is selected, the `FileContentView` will continue to display the content or icon of the *last selected file*.
   *   **Filename Display:** The name of the currently displayed file should be visible within the `FileContentView` area (e.g., as the view's navigation title).
   *   **Unsaved Indicator:** The underlying `isDirty` state exists in the ViewModel, but no visual indicator is currently shown in the UI.

**3. Core Functionality:**
   *   **State Management:**
        *   Introduce a new `ObservableObject` class, tentatively `FileContentViewModel`, responsible for managing the state related to the currently displayed file:
            *   URL of the file being displayed.
            *   Loaded file content (for `TextEditor`).
            *   Original file content (for dirty checking).
            *   `isDirty` flag (Bool).
            *   Indicator if the file is plain text (`isPlainText` flag).
            *   File icon (optional, if non-text).
            *   Any relevant error state (`errorMessage` string).
        *   `FileContentView` will observe this `FileContentViewModel`.
        *   `FileContentView` observes `FolderViewModel.selectedItem` via `.onChange` and calls `FileContentViewModel.loadFile(url:)` when a file is selected.
   *   **File Loading:**
        *   When `FolderViewModel.selectedItem` changes and represents a *file*:
            *   The system determines if the file is likely text-based (e.g., based on UTI conforming to `public.text` or specific known extensions).
            *   **If Text:** Attempt to read the file content as a String (assume UTF-8 initially).
                *   On success: Store the content in `FileContentViewModel` (both current and original), set `isDirty` to `false`, clear non-text flag.
                *   On read error: Set the `errorMessage` property in `FileContentViewModel`, which is displayed in the UI.
            *   **If Non-Text:** Set the `isPlainText=false` flag in `FileContentViewModel`, fetch the file icon.
        *   If `FolderViewModel.selectedItem` changes and represents a *directory*: The `FileContentViewModel` state remains unchanged (showing the last file).
   *   **Editing:**
        *   The `TextEditor` in `FileContentView` will be bound to the current content property in `FileContentViewModel`.
        *   Any change to the text content will trigger a comparison against the original content to set the `isDirty` flag in `FileContentViewModel`.
        *   The unsaved indicator in the UI will reflect the `isDirty` state.
   *   **Saving:**
        *   A save action will be triggered via the standard Cmd+S keyboard shortcut.
        *   The save action should only be invocable if `isDirty` is `true`.
        *   The action attempts to write the current content from `FileContentViewModel` back to the file URL (using UTF-8).
        *   **On success:** Update the "original content" in `FileContentViewModel` to match the saved content, set `isDirty` to `false`.
        *   **On save error:** Set the `errorMessage` property in `FileContentViewModel`, which is displayed in the UI. Do *not* clear the dirty state.

**4. Non-Functional Requirements:**
   *   Reading and saving files should feel reasonably responsive for typical text file sizes.
   *   Error messages displayed in the UI should be clear and informative.
   *   Assume UTF-8 encoding for reading/writing text files.

**5. Future Considerations / Out of Scope for Phase 3:**
   *   Syntax highlighting in the editor.
   *   Handling extremely large files (memory usage, performance).
   *   Explicit file encoding detection or selection.
   *   Line endings configuration.
   *   "Save As" functionality.
   *   Closing files explicitly (relevant if multiple tabs/editors are ever supported). 