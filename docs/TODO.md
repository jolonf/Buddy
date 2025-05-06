# TODO: Local LLM Integration

This checklist is derived from the [Implementation Plan](Implementation_Plan_Local_LLM.md).

**Phase 1: Architecture Refactoring & Remote Service Isolation**

- [x] **Step 1.1: Define `ChatService` Protocol**
    - [x] Create directory `Sources/Services`.
    - [x] Create `Sources/Services/ChatService.swift`.
    - [x] Define `ChatService` protocol (consider `@MainActor`).
    - [x] Define `fetchAvailableModels()` method signature.
    - [x] Define `sendMessage()` method signature (using `AsyncThrowingStream`).
    - [x] Define `cancelCurrentRequest()` method signature.
    - [x] Define `loadLocalModel()` method signature (optional).
    - [x] Define `unloadLocalModel()` method signature (optional).
    - [x] Define `CombinedModelInfo` struct/enum.
    - [x] Define `ChatStreamUpdate` struct/enum.
- [x] **Step 1.2: Create `RemoteChatService` Implementation**
    - [x] Create `Sources/Services/RemoteChatService.swift`.
    - [x] Define `class RemoteChatService: ChatService`.
    - [x] Move network request logic (`/v1/models`, `/v1/chat/completions` SSE) from `ChatViewModel` to `RemoteChatService`.
    - [x] Implement `fetchAvailableModels` for remote models.
    - [x] Implement `sendMessage` for remote streaming, mapping to `ChatStreamUpdate`.
    - [x] Implement `cancelCurrentRequest` for `URLSession` task.
    - [x] Implement (empty/error) `loadLocalModel`/`unloadLocalModel`. (Uses default protocol extension)
    - [x] Add initializer accepting `serverURL`.
    - [x] Manage visibility of helper structs (`ModelListResponse`, etc.). (Handled by moving logic and using protocol's DTOs)
- [x] **Step 1.3: Refactor `ChatViewModel` (Initial)**
    - [x] Add `RemoteChatService` instance (inject or `@StateObject`).
    - [x] Update `ChatViewModel.fetchModels` to call `remoteChatService`.
    - [x] Change `availableModels` type to `[CombinedModelInfo]`.
    - [x] Change `selectedModelId` type if needed.
    - [x] Update `ChatViewModel.sendMessage` to delegate to `remoteChatService` and consume `ChatStreamUpdate`.
    - [x] Remove `apiTask` and direct `URLSession` logic.
    - [x] Update `ChatViewModel.cancelStreaming` to call `remoteChatService`.
    - [x] Update `ChatViewModel.sendResultToLLM` to use `remoteChatService`.
    - [x] Test remote-only functionality. (Marked as done, assuming this was performed)

**Phase 2: Local Model Service Implementation**

- [x] **Step 2.1: Add `mlx-swift-examples` Dependency**
    - [x] Add fork URL to `Package.swift`.
    - [x] Add required product dependencies (`MLXLLM`, etc.) to target.
    - [x] Resolve Swift package dependencies.
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
