**Implementation Plan: Local LLM Integration**

**Goal:** Integrate local MLX models into the Buddy application, allowing users to select and use them alongside remote models, based on the approved PRD (`docs/PRD_Local_LLM_Integration.md`).

**Developer:** [Assignee Name]

**Phase 1: Architecture Refactoring & Remote Service Isolation**

*   **Step 1.1: Define `ChatService` Protocol**
    *   Create a new directory `Sources/Services`.
    *   Create `Sources/Services/ChatService.swift`.
    *   Define a protocol `ChatService` adhering to `@MainActor` if methods directly publish UI changes or ensure implementers handle main thread dispatch.
    *   Define required methods:
        *   `func fetchAvailableModels() async throws -> [CombinedModelInfo]` (Define `CombinedModelInfo` struct/enum below).
        *   `func sendMessage(history: [ChatMessage], systemPrompt: String, model: CombinedModelInfo, interactionMode: InteractionMode) -> AsyncThrowingStream<ChatStreamUpdate, Error>` (Define `ChatStreamUpdate` struct/enum below).
        *   `func cancelCurrentRequest()`
        *   `(Optional but Recommended)` `func loadLocalModel(_ model: CombinedModelInfo) async throws` - May simplify `ChatViewModel` logic.
        *   `(Optional but Recommended)` `func unloadLocalModel()`
    *   Define helper types:
        *   `struct CombinedModelInfo: Identifiable, Hashable { let id: String; enum ModelType { case local, remote }; let type: ModelType; let displayName: String }` (Adapt as needed).
        *   `enum ChatStreamUpdate { case contentDelta(String); case usage(StreamChunk.Usage); case firstTokenTime(TimeInterval); case finalMetrics(tps: Double?, tokenCount: Int); case error(Error) }` (Adapt based on required feedback granularity).

*   **Step 1.2: Create `RemoteChatService` Implementation**
    *   Create `Sources/Services/RemoteChatService.swift`.
    *   Define `class RemoteChatService: ChatService`.
    *   **Move Existing Logic:** Transfer all network request logic (`URLSession`, SSE parsing, JSON decoding for `/v1/models` and `/v1/chat/completions`) from `ChatViewModel` into `RemoteChatService`.
    *   **Adapt to Protocol:** Implement the `ChatService` methods using the moved logic.
        *   `fetchAvailableModels`: Fetch from server, map results to `[CombinedModelInfo]` with `type = .remote`.
        *   `sendMessage`: Construct `ChatCompletionRequest`, perform the `URLSession.shared.bytes(for:)` request, parse the SSE stream, and yield `ChatStreamUpdate` values through the `AsyncThrowingStream`. Handle mapping `StreamChunk` to `ChatStreamUpdate`.
        *   `cancelCurrentRequest`: Implement task cancellation for the `URLSession` task.
        *   `loadLocalModel`/`unloadLocalModel`: Provide empty implementations or throw an error (not applicable).
    *   **Dependency Injection:** Modify initializer to accept the `serverURL` string.
    *   Make helper structs like `ModelListResponse`, `StreamChunk`, `ChatCompletionRequest` internal to the `Services` group or keep them accessible if needed by `ChatViewModel` (though ideally, `ChatViewModel` only deals with `CombinedModelInfo` and `ChatStreamUpdate`).

*   **Step 1.3: Refactor `ChatViewModel` (Initial)**
    *   Add `@StateObject` or inject instances of `RemoteChatService` (and later `LocalChatService`). For simplicity, start with just `RemoteChatService`.
        ```swift
        // Example: Choose dependency injection or @StateObject
        private let remoteChatService: RemoteChatService
        // private let localChatService: LocalChatService // Add later

        init(folderViewModel: FolderViewModel, commandRunnerViewModel: CommandRunnerViewModel, remoteChatService: RemoteChatService /*, localChatService: LocalChatService */) {
            // ... existing init ...
            self.remoteChatService = remoteChatService
            // self.localChatService = localChatService // Add later
            // ... existing init ...
        }
        ```
    *   Modify `ChatViewModel.fetchModels`:
        *   Call `remoteChatService.fetchAvailableModels()`.
        *   Update `@Published var availableModels: [CombinedModelInfo]` (change type).
        *   Update `@Published var selectedModelId: CombinedModelInfo.ID?` (or keep as String if `CombinedModelInfo.id` remains the unique string). Handle selection logic.
        *   Update error handling (`connectionError`).
    *   Modify `ChatViewModel.sendMessage`:
        *   Delegate the call to `remoteChatService.sendMessage(history: ..., systemPrompt: ..., model: ..., interactionMode: ...)` using the currently selected *remote* model.
        *   Consume the `AsyncThrowingStream` from the service.
        *   Update `@Published` properties (`messages`, `isSendingMessage`, `isAwaitingFirstToken`, metrics like `ttft`, `tps`, etc.) based on the received `ChatStreamUpdate` values.
        *   Remove the direct `URLSession` task logic (`apiTask`). The stream's lifecycle manages the task.
    *   Modify `ChatViewModel.cancelStreaming`: Call `remoteChatService.cancelCurrentRequest()`.
    *   Modify `ChatViewModel.sendResultToLLM`: Adapt to use `remoteChatService.sendMessage` similarly to `sendMessage`.
    *   **Testing:** Verify the application still works correctly *only* with remote models after this refactoring.

**Phase 2: Local Model Service Implementation**

*   **Step 2.1: Add `mlx-swift-examples` Dependency**
    *   Modify `Package.swift`:
        *   Add the fork: `.package(url: "https://github.com/jolonf/mlx-swift-examples", branch: "main")`.
        *   Add products (e.g., `MLXLLM`, `MLX`, `MLXRandom`, `MLXNN`, `Tokenizers`) as dependencies to your main app target (`Buddy`).
    *   Resolve dependencies (`swift package resolve` or via Xcode).

*   **Step 2.2: Create `LocalChatService` Implementation**
    *   Create `Sources/Services/LocalChatService.swift`.
    *   Define `class LocalChatService: ChatService`. Import `MLX`, `MLXLLM`, `Foundation`, etc.
    *   **Model Discovery:**
        *   Implement logic to scan the user's `Downloads` directory (`FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)`).
        *   Define criteria for identifying MLX model folders (e.g., presence of `config.json`, `tokenizer.json`, `.safetensors` files). Consult `MLXChatExample` or `mlx-swift-examples` docs.
        *   Implement `fetchAvailableModels`: Perform scan, map valid finds to `[CombinedModelInfo]` with `type = .local`. Handle errors (permissions, folder not found).
    *   **MLX Integration:**
        *   Add properties to hold the loaded MLX model, tokenizer, and configuration (`LLM`, `Tokenizer`, etc.). Manage their state (loaded/unloaded).
        *   Implement `loadLocalModel`: Use MLX APIs (e.g., `LLM.load(configuration:)`) to load the specified model into memory. Store the loaded instances. Handle potential errors (memory, file format). Unload any previously loaded model first. Report progress/errors (e.g., via Combine PassthroughSubject or callbacks).
        *   Implement `unloadLocalModel`: Release references to the MLX model objects to free memory.
        *   Implement `sendMessage`:
            *   Ensure the correct model is loaded (call `loadLocalModel` if necessary).
            *   Prepare the prompt string using the `history` and `systemPrompt`.
            *   Use MLX's generation API (e.g., `LLM.generate(prompt: ...)` which likely returns an `AsyncStream`).
            *   Adapt the MLX stream output (tokens, stats) to yield `ChatStreamUpdate` values via the `AsyncThrowingStream` required by the protocol. Ensure prompt caching is implicitly used by the library.
    *   **Cancellation:** Implement `cancelCurrentRequest` if MLX's generation stream supports cancellation.
    *   **State Management:** Manage internal state for the currently loaded model, loading progress, and errors.

**Phase 3: ViewModel and View Integration**

*   **Step 3.1: Update `ChatViewModel` (Full Integration)**
    *   Add `LocalChatService` instance (inject or create).
    *   Modify `fetchModels`: Call *both* `remoteChatService.fetchAvailableModels()` and `localChatService.fetchAvailableModels()`. Combine results into `availableModels`. Handle errors from either service gracefully (e.g., show partial lists).
    *   Add state for local model loading: `@Published var localModelLoadingState: LoadingState = .idle` (where `LoadingState` could be `.idle`, `.loading(progress: Double)`, `.error(String)`, `.loaded(CombinedModelInfo)`).
    *   Modify selection logic (`selectedModelId`) to work with `CombinedModelInfo`.
    *   Modify `sendMessage`:
        *   Determine if `selectedModelId` corresponds to a local or remote model (`CombinedModelInfo.type`).
        *   If local:
            *   Check `localModelLoadingState`. If not loaded or different model selected, call `localChatService.loadLocalModel()` first (handle UI state via `localModelLoadingState`).
            *   Once loaded, call `localChatService.sendMessage(...)`.
        *   If remote: Call `remoteChatService.sendMessage(...)`.
        *   Update stream consumption logic to handle `ChatStreamUpdate` from either service.
    *   Modify `cancelStreaming`: Call `cancelCurrentRequest` on the *active* service (whichever is currently generating).
    *   Modify `sendResultToLLM`: Determine original message type (local/remote) and delegate to the correct service.
    *   Integrate loading feedback: Subscribe to progress/error publishers/callbacks from `LocalChatService` and update `localModelLoadingState`.

*   **Step 3.2: Update `ChatView`**
    *   Modify the `Picker` / model list area:
        *   Iterate over `viewModel.availableModels`.
        *   Use `Section` views to group by `CombinedModelInfo.type` ("Local Models", "Remote Models").
        *   Display connection errors/status for the remote section.
        *   For local models, display loading status based on `viewModel.localModelLoadingState` and the specific model ID (e.g., show a spinner or progress indicator next to the model being loaded).
        *   Disable selection of other local models while one is loading.
        *   Ensure selecting a model updates `viewModel.selectedModelId`.
    *   Ensure the refresh button triggers the updated `fetchModels` in the ViewModel.
    *   Make sure error messages (`connectionError`, local loading errors) are displayed clearly.

**Phase 4: Testing & Refinement**

*   **Step 4.1: Comprehensive Testing:**
    *   **Remote:** Verify all existing remote functionality (model fetching, chat, streaming, actions, cancellation, error handling).
    *   **Local Discovery:** Test finding models in `Downloads`, handling missing/empty directory, handling invalid model folders.
    *   **Local Loading:** Test loading different models, switching between them, success/failure scenarios (memory, file errors), progress reporting.
    *   **Local Chat:** Test generation, streaming, prompt caching effects (if observable), actions, cancellation.
    *   **UI:** Test model list display, section headers, loading indicators, error messages, responsiveness.
    *   **Edge Cases:** Test interactions between local/remote selection, cancellation during loading, etc.
*   **Step 4.2: Bug Fixing & Polish:** Address any issues found during testing. Refine UI elements and error messages for clarity.
*   **Step 4.3: (Optional) Stretch Goals:** Implement resource warnings if MLX APIs allow querying required/available memory. 