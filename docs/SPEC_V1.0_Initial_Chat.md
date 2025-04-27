## Functional Specification: LLM Coding Agent Explorer (Version 1.0)

**Note:** This document describes the *initial* V1.0 scope. Features like folder interaction, file editing, command running, and agent actions were added later and are detailed in subsequent specification documents (V2.0 - V5.0).

**1. Introduction**

This document outlines the functional requirements for the initial version (V1.0) of the LLM Coding Agent Explorer application. The goal of this version is to provide a basic chat interface for interacting with Large Language Models (LLMs) hosted locally via LM Studio, running on macOS.

**2. Goals**

*   Establish a connection to a local LM Studio instance.
*   Allow users to select from currently loaded models in LM Studio.
*   Provide a simple, real-time chat interface for interacting with the selected LLM.
*   Serve as a foundation for future exploration of LLM capabilities for coding agent development.

**3. Target Platform**

*   Primary: macOS (Apple Silicon recommended)
*   Technology: SwiftUI (Universal App structure, but macOS focus for V1)

**4. Core Features**

**4.1. LM Studio Connection**

*   **Server Address Configuration:**
    *   The application currently uses a fixed server address for the LM Studio server.
    *   The default value is hardcoded as `http://localhost:1234`.
    *   API paths (e.g., `/v1/models`, `/v1/chat/completions`) are appended directly to this fixed base URL.
*   **Connection Status & Model Loading:**
    *   Upon launch, and whenever the server address is changed, the application shall attempt to connect to the LM Studio server by making a `GET` request to the `/v1/models` endpoint.
    *   **Success:** If the connection is successful and models are returned:
        *   A model selection UI element (e.g., a Picker/Dropdown) shall be populated with the names/identifiers of the loaded models returned by the API.
        *   The model selection UI shall be enabled, allowing the user to choose a model.
        *   The first model in the list can be selected by default.
    *   **Failure:** If the connection fails (e.g., server down, incorrect address, non-200 response):
        *   The model selection UI shall be disabled (e.g., greyed out).
        *   A clear error message shall be displayed to the user indicating the connection failure (e.g., "Cannot connect to LM Studio at [URL]. Check if the server is running and the address is correct."). This message could appear near the model selector or inline in the chat view if a chat action triggers the error.
*   **API Endpoint:** The application shall use the `GET /v1/models` endpoint to retrieve the list of currently *loaded* models.

**4.2. Chat Interface**

*   **Layout:**
    *   A standard chat interface layout shall be used.
    *   A scrollable view shall display the conversation history, with alternating message bubbles for user input and LLM responses.
    *   A text input field shall be located at the bottom of the view for the user to type their messages.
    *   A "Send" button shall be placed adjacent to the text input field.
    *   A "Clear Chat" button or menu option shall be provided to clear the current conversation history from the view.
*   **Sending Messages:**
    *   When the user enters text and taps "Send" (or presses Enter), the application shall:
        *   Append the user's message to the chat view.
        *   Construct a request payload conforming to the OpenAI `/v1/chat/completions` API schema. This includes the selected model, the conversation history (formatted as an array of messages with `role` and `content`), and the parameter `stream: true`.
        *   Send a `POST` request to the `/v1/chat/completions` endpoint of the configured LM Studio server.
*   **Receiving & Displaying Responses:**
    *   The application shall handle the Server-Sent Events (SSE) stream returned by the `/v1/chat/completions` endpoint.
    *   As data chunks (tokens) arrive in the stream:
        *   The application shall progressively append the received text content to the LLM's message bubble in the chat view, providing a real-time, word-by-word display.
        *   The application should aim to render basic Markdown formatting (e.g., bold, italics, code blocks ` ``` `) if SwiftUI makes this reasonably straightforward. If complex, plain text rendering is acceptable for V1.
    *   The application needs to correctly parse the SSE stream to extract the message content (typically within `delta.content`).
*   **Error Handling (Chat):**
    *   If an error occurs during the chat request/response (e.g., API error from LM Studio, network issue mid-stream), an informative error message shall be displayed in a dedicated status area above the chat history.
*   **Persistence:** The chat history shall *not* persist between application launches in V1.0. Clearing the chat or restarting the app will result in an empty chat view.

**5. Non-Functional Requirements**

*   **UI/UX:** The interface should be clean, intuitive, and follow standard macOS design conventions.
*   **Performance:** The app should remain responsive during streaming LLM responses. UI updates should be efficient.
*   **Technology:** SwiftUI, targeting macOS.

*   Technology: SwiftUI, targeting macOS.

**6. Future Considerations (Out of Scope for V1.0)**

*   Chat history persistence (local storage, Core Data, CloudKit).
*   Support for LM Studio's native API (`/api/v0/`) for potentially richer model information.
*   Bonjour discovery for LM Studio server.
*   More advanced Markdown rendering.
*   Support for parameters like temperature, max tokens, etc.
*   ~~System prompt configuration.~~ (Basic file-based system prompt loading implemented).
*   Multi-chat session management.
*   Integration with other LLM hosting services (Ollama, Cloud APIs).
*   ~~Features specific to coding agent exploration (e.g., file context, tool use simulation).~~ (Covered in later specs V2.0-V5.0). 