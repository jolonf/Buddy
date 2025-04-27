## Functional Specification: Buddy - Phase 2: Folder View (Version 2.0)

**Note:** This document describes the scope for Phase 2. Features like command running and agent actions were added later and are detailed in subsequent specification documents.

**1. Introduction**

This document outlines the functional requirements for Phase 2 of the Buddy application. Building upon the basic chat functionality established in Phase 1, this phase focuses on adding a persistent, lazy-loading file system browser panel, similar to the Explorer view in VS Code or the Project Navigator in Xcode. This panel will allow users to select and view the structure of a local project folder.

**2. Goals**

*   Integrate a sidebar view for navigating a local file system directory structure.
*   Allow the user to explicitly select a root project folder via a system open panel.
*   Persist the selected folder across application launches securely using security-scoped bookmarks.
*   Display a hierarchical, expandable/collapsible tree view of the selected folder's contents.
*   Implement lazy loading for folder contents to ensure UI responsiveness with large directories.
*   Establish the primary UI structure (`NavigationSplitView`) to accommodate the folder view alongside the chat interface, preparing for future file content display.

**3. UI Changes**

*   **Main Layout (`BuddyApp.swift` / `ContentView.swift`):**
    *   The root view will be refactored to use a `NavigationSplitView`.
    *   **Sidebar:** Hosts the new `FolderView`.
    *   **Content:** Hosts the existing chat interface (likely the current `ContentView` structure, possibly renamed or refactored).
*   **Folder View (New: `FolderView.swift`):**
    *   **Initial State:** When no folder is selected (e.g., first launch, or persisted bookmark fails), the sidebar displays a standard placeholder view (e.g., using `ContentUnavailableView`) indicating no folder is selected and offering a button to select one.
    *   **Active State:** Once a folder is successfully selected and accessed, the sidebar displays a hierarchical tree view of its contents.
        *   **Tree Items:** Each item represents a file or folder.
        *   **Expansion:** Folders are expandable/collapsible (e.g., using `List` with a `children` key path).
        *   **Icons:** Standard SF Symbols will be used initially (e.g., `folder` for directories, `doc` for files).
        *   **Sorting:** Within each directory level, items are sorted alphabetically, with folders listed before files.
        *   **Selection:** Selecting an item in the tree updates a published `@Published var selectedItem: FileSystemItem?` property in the `FolderViewModel`. This allows other views (like a file content view) to observe and react to the selection.
*   **"Select Project Folder" Button:**
    *   Located within the `FolderView` (visible as part of the initial/empty state view).
    *   Triggers a system file open panel configured to select directories only.

**4. Core Functionality**

*   **Folder Selection:**
    *   Utilize SwiftUI's `.fileImporter` modifier to allow the user to choose a directory.
*   **Persistence:**
    *   Upon successful folder selection via `.fileImporter`, generate security-scoped bookmark data from the chosen folder's URL.
    *   Store this bookmark `Data` persistently using `@AppStorage` (e.g., key: `"selectedFolderBookmarkData"`).
    *   On application launch, attempt to retrieve the bookmark `Data` from `@AppStorage`.
    *   If `Data` exists, attempt to resolve it back to a URL using `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)`. Handle potential errors and stale bookmarks (e.g., by clearing the stored data and showing the "Select Folder" button).
    *   Crucially, call `selectedURL.startAccessingSecurityScopedResource()` before attempting to read the folder contents for the session.
    *   Implement corresponding `selectedURL.stopAccessingSecurityScopedResource()` calls when access is no longer needed (e.g., potentially on app termination or if the user selects a different folder in the future - careful lifecycle management required).
*   **File System Model (New Files Likely):**
    *   Define a data structure (e.g., `FileSystemItem`) to represent files and folders, conforming to `Identifiable` and potentially `ObservableObject` if needed for lazy loading state. It should include properties like `name`, `url`, `isDirectory`, and an optional, lazily populated `children` array (`[FileSystemItem]?`).
    *   Implement logic (likely in a new `FolderViewModel.swift` or similar service class) to:
        *   Read the contents of a directory URL using `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`.
        *   Filter out hidden files (e.g., files starting with ".").
        *   Map the results to `FileSystemItem` objects.
        *   Sort the items (folders first alphabetically, then files alphabetically).
        *   Handle file system access errors gracefully (e.g., permissions issues even with bookmark access).
*   **Lazy Loading:**
    *   The `children` property of a folder `FileSystemItem` should only be populated when the user expands that folder in the UI for the first time.
    *   Subsequent expansions can show the cached children. A refresh mechanism might be considered later.

**5. Non-Functional Requirements**

*   **Responsiveness:** The UI, particularly the chat interface, should remain responsive while the sidebar loads initial folder contents or expands sub-folders. Lazy loading is key to this.
*   **Security:** Access to the selected folder must rely on security-scoped bookmarks for persistence, respecting macOS privacy controls.

**6. Future Considerations (Out of Scope for Phase 2)**

*   ~~Displaying file content in a detail view when a file is selected.~~ (Implemented)
*   Implementing file operations (create, rename) via context menus or buttons. (Delete implemented).
*   Adding a search/filter bar to the folder view.
*   Supporting multiple project roots or workspaces.
*   ~~Displaying actual file icons (using `NSWorkspace` on macOS) instead of generic SF Symbols.~~ (Basic support implemented for non-text files).
*   Manual refresh button for the folder view.
*   ~~Handling changes to the file system made outside the application while it's running.~~ (Implemented via `DispatchSource` monitoring).