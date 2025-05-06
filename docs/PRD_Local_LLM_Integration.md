## PRD: Local LLM Integration

**1. Introduction & Goal**

This document outlines the requirements for integrating local Large Language Models (LLMs) directly into the Buddy application. The goal is to allow users to run chat interactions and execute actions using models stored on their local machine, without relying on a remote server. This will enhance privacy, enable offline use, and offer users more model flexibility. The integration will leverage a specific fork of the `mlx-swift-examples` library ([https://github.com/jolonf/mlx-swift-examples](https://github.com/jolonf/mlx-swift-examples)) which includes prompt caching support.

**2. User Experience**

*   **Model Selection:**
    *   The existing model selection UI (`ChatView.swift`) will be modified to display two distinct sections:
        *   **Remote Models:** Lists models fetched from the configured server URL (e.g., `http://localhost:1234`). If the server is unreachable, this section should indicate the connection status (e.g., "Not Connected", "Error fetching models").
        *   **Local Models:** Lists available MLX models found in the user's `Downloads` directory.
    *   Selecting a *local* model will initiate the loading process for that model.
    *   If another local model is already loaded, it will be automatically unloaded before the new one starts loading.
    *   Selecting a *remote* model will work as it currently does.
*   **Loading Feedback:**
    *   When a local model is being loaded, the UI should display clear feedback (e.g., a progress bar or spinner within the model selection area or a status message).
    *   If loading fails (e.g., insufficient memory, file error), a clear error message should be displayed to the user (e.g., in the status area).
*   **Chat Interaction:** The core chat interface and functionality (sending messages, receiving streamed responses, viewing history) should remain consistent regardless of whether a local or remote model is selected.
*   **Agent Mode & Actions:** Agent Mode and the associated action execution mechanism must function identically for both local and remote models, utilizing the same system prompts.

**3. Technical Architecture & Refactoring**

*   **Chat Service Abstraction:**
    *   A `ChatService` protocol will be defined to abstract the core LLM interaction logic. This protocol will include methods for:
        *   Fetching available models (distinguishing between local and remote).
        *   Sending chat messages (handling history, system prompts, and streaming).
        *   Cancelling ongoing generation requests.
        *   Loading/unloading local models (if applicable).
*   **Implementations:**
    *   `RemoteChatService`: A new class implementing `ChatService`. It will encapsulate the existing logic from `ChatViewModel` for communicating with the remote (Ollama/LM Studio) server via HTTP requests.
    *   `LocalChatService`: A new class implementing `ChatService`. It will be responsible for:
        *   Discovering MLX models in the `~/Downloads` directory.
        *   Using the `mlx-swift-examples` fork's library (inspired by `MLXChatExample`/`MLXService.swift`) to load/unload models.
        *   Performing text generation using the loaded MLX model.
        *   Implementing streaming responses.
        *   Leveraging the fork's prompt caching feature automatically.
        *   Reporting loading progress and errors.
*   **ViewModel Refactoring:**
    *   `ChatViewModel` will be refactored to hold references to *both* `RemoteChatService` and `LocalChatService` (or potentially a single `ChatService` instance that internally manages the switch based on user selection).
    *   `ChatViewModel` will delegate model fetching and chat operations to the appropriate service based on the user's model selection.
    *   Direct network call logic (`URLSession`, JSON decoding for remote API) will be moved to `RemoteChatService`.
    *   State management related to connection errors, model lists (remote vs. local), loading status, and the selected model will remain in/be adapted within `ChatViewModel`.
*   **View Layer:**
    *   `ChatView` will be updated to:
        *   Display the separate sections for local and remote models based on data provided by `ChatViewModel`.
        *   Reflect the loading status of local models.
        *   Trigger the appropriate loading/selection actions in `ChatViewModel`.

**4. Local Model Handling (`LocalChatService`)**

*   **Discovery:** Scan the `~/Downloads` directory for potential MLX model directories/files (based on naming conventions or metadata expected by the `mlx-swift-examples` library).
*   **Format:** Assume models are in the format compatible with the `mlx-swift-examples` library, originating from Hugging Face.
*   **Loading/Unloading:** Implement logic to load a selected model into memory using the library's APIs and unload any previously loaded model to conserve resources.
*   **Resource Management:** (Stretch Goal) If the MLX library provides APIs to query model resource requirements or available system resources (RAM), attempt to provide feedback or warnings to the user before loading potentially very large models.
*   **Prompt Caching:** Utilize the prompt caching feature provided by the `jolonf/mlx-swift-examples` fork implicitly during generation.
*   **Error Handling:** Gracefully handle errors during model discovery, loading (e.g., file not found, format errors, memory issues), and generation.

**5. Action Handling**

The existing `ActionHandler` and its interaction mechanism (triggered after receiving a complete response, sending results back) must work seamlessly with responses generated by the `LocalChatService`. The system prompts defining the action format remain unchanged.

**6. Platform**

The application, including local model support, will target macOS only.

**7. Non-Goals (Initial Phase)**

*   Support for model formats other than MLX.
*   Automatic downloading of new local models.
*   Advanced model management UI (e.g., deleting models from disk).
*   Support for iOS or visionOS for local models.
*   Detailed resource monitoring beyond basic warnings (if feasible). 