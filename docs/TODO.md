# TODO: Local LLM Integration

This checklist is derived from the [Implementation Plan](Implementation_Plan_Local_LLM.md).

**Phase 1: Architecture Refactoring & Remote Service Isolation**

- [ ] **Step 1.1: Define `ChatService` Protocol**
    - [ ] Create directory `Sources/Services`.
    - [ ] Create `Sources/Services/ChatService.swift`.
    - [ ] Define `ChatService` protocol (consider `@MainActor`).
    - [ ] Define `fetchAvailableModels()` method signature.
    - [ ] Define `sendMessage()` method signature (using `AsyncThrowingStream`).
    - [ ] Define `cancelCurrentRequest()` method signature.
    - [ ] Define `loadLocalModel()` method signature (optional).
    - [ ] Define `unloadLocalModel()` method signature (optional).
    - [ ] Define `CombinedModelInfo` struct/enum.
    - [ ] Define `ChatStreamUpdate` struct/enum.
- [ ] **Step 1.2: Create `RemoteChatService` Implementation**
    - [ ] Create `Sources/Services/RemoteChatService.swift`.
    - [ ] Define `class RemoteChatService: ChatService`.
    - [ ] Move network request logic (`/v1/models`, `/v1/chat/completions` SSE) from `ChatViewModel` to `RemoteChatService`.
    - [ ] Implement `fetchAvailableModels` for remote models.
    - [ ] Implement `sendMessage` for remote streaming, mapping to `ChatStreamUpdate`.
    - [ ] Implement `cancelCurrentRequest` for `URLSession` task.
    - [ ] Implement (empty/error) `loadLocalModel`/`unloadLocalModel`.
    - [ ] Add initializer accepting `serverURL`.
    - [ ] Manage visibility of helper structs (`ModelListResponse`, etc.).
- [ ] **Step 1.3: Refactor `ChatViewModel` (Initial)**
    - [ ] Add `RemoteChatService` instance (inject or `@StateObject`).
    - [ ] Update `ChatViewModel.fetchModels` to call `remoteChatService`.
    - [ ] Change `availableModels` type to `[CombinedModelInfo]`.
    - [ ] Change `selectedModelId` type if needed.
    - [ ] Update `ChatViewModel.sendMessage` to delegate to `remoteChatService` and consume `ChatStreamUpdate`.
    - [ ] Remove `apiTask` and direct `URLSession` logic.
    - [ ] Update `ChatViewModel.cancelStreaming` to call `remoteChatService`.
    - [ ] Update `ChatViewModel.sendResultToLLM` to use `remoteChatService`.
    - [ ] Test remote-only functionality.

**Phase 2: Local Model Service Implementation**

- [ ] **Step 2.1: Add `mlx-swift-examples` Dependency**
    - [ ] Add fork URL to `Package.swift`.
    - [ ] Add required product dependencies (`MLXLLM`, etc.) to target.
    - [ ] Resolve Swift package dependencies.
- [ ] **Step 2.2: Create `LocalChatService` Implementation**
    - [ ] Create `Sources/Services/LocalChatService.swift`.
    - [ ] Define `class LocalChatService: ChatService`. Import necessary modules.
    - [ ] Implement model discovery logic (scan `Downloads` dir).
    - [ ] Implement `fetchAvailableModels` for local models.
    - [ ] Add properties for loaded MLX model/tokenizer.
    - [ ] Implement `loadLocalModel` using MLX APIs, handle unloading previous.
    - [ ] Implement `unloadLocalModel`.
    - [ ] Implement `sendMessage` using MLX generation, map stream to `ChatStreamUpdate`.
    - [ ] Implement `cancelCurrentRequest` for MLX stream (if possible).
    - [ ] Manage internal state (loading progress, errors).

**Phase 3: ViewModel and View Integration**

- [ ] **Step 3.1: Update `ChatViewModel` (Full Integration)**
    - [ ] Add `LocalChatService` instance.
    - [ ] Update `fetchModels` to call both services and combine results.
    - [ ] Add `@Published var localModelLoadingState: LoadingState`.
    - [ ] Update `selectedModelId` handling for `CombinedModelInfo`.
    - [ ] Update `sendMessage` to delegate to correct service based on model type.
    - [ ] Handle calling `loadLocalModel` before sending if needed.
    - [ ] Update `cancelStreaming` to call the active service.
    - [ ] Update `sendResultToLLM` to delegate to the correct service.
    - [ ] Integrate loading feedback from `LocalChatService` into `localModelLoadingState`.
- [ ] **Step 3.2: Update `ChatView`**
    - [ ] Modify model list/Picker to use `Section` for Local/Remote models.
    - [ ] Display remote connection status in its section.
    - [ ] Display local model loading status (`localModelLoadingState`) next to relevant models.
    - [ ] Disable selection appropriately during loading.
    - [ ] Ensure refresh button works with updated `fetchModels`.
    - [ ] Ensure error messages are displayed clearly.

**Phase 4: Testing & Refinement**

- [ ] **Step 4.1: Comprehensive Testing**
    - [ ] Test remote functionality.
    - [ ] Test local model discovery.
    - [ ] Test local model loading/unloading.
    - [ ] Test local chat generation/streaming/actions.
    - [ ] Test UI updates (lists, loading states, errors).
    - [ ] Test edge cases.
- [ ] **Step 4.2: Bug Fixing & Polish**
    - [ ] Address issues found during testing.
    - [ ] Refine UI/UX.
- [ ] **Step 4.3: (Optional) Stretch Goals**
    - [ ] Implement resource warnings. 