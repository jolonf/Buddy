# Buddy

## Overview

Buddy is a macOS SwiftUI application developed as an experiment in AI coding with local LLMs connecting to LM Studio.

**Disclaimer:** This project is purely experimental and intended for learning and exploration purposes. It is **not** a polished product, is likely unstable, and is not suitable for production use.

## Purpose

The primary goal of Buddy is to serve as a testbed for integrating LLMs (specifically, models served locally via [LM Studio](https://lmstudio.ai/)) into a development-like workflow. It explores concepts such as:

*   Real-time chat interaction with LLMs.
*   Browsing and interacting with local file systems.
*   Viewing and editing code files.
*   Executing shell commands within a project context.
*   Enabling the LLM to perform file system actions (read, list, edit) in an "Agent" mode.

## Features (Based on Development Phases)

1.  **Chat Interface:** Connects to a local LM Studio instance (`http://localhost:1234` by default) and provides a chat interface to interact with loaded models via the OpenAI-compatible API. Supports streaming responses.
2.  **Folder View:** A sidebar allows selecting a local project folder (using security-scoped bookmarks for persistent access) and browsing its contents in a hierarchical view.
3.  **File Editor:** Displays the content of selected text files and allows basic editing with save functionality (Cmd+S). Shows icons for non-text files.
4.  **Command Runner:** An integrated panel within the file view allows executing shell commands in the context of the selected project folder and displays the output.
5.  **LLM File System Actions:** An experimental "Agent" mode allows the LLM to request file reads, directory listings, and perform file edits based on structured `ACTION:` commands parsed from its responses.

## Building and Running

This project is built using the Swift Package Manager and defines a SwiftUI application executable named "Buddy".

1.  **Prerequisites:**
    *   macOS with the Swift toolchain installed (available with Xcode or separately).
    *   (Optional but recommended for full functionality) [LM Studio](https://lmstudio.ai/) running locally with a loaded model.

2.  **Running (Using `swift run`):**
    *   Navigate to the project's root directory in your terminal (the directory containing `Package.swift`).
    *   Execute the command: `swift run Buddy` (or simply `swift run` as it's the only executable product).
    *   This command compiles the source code (including SwiftUI views) and then launches the graphical "Buddy" application window.

**Note:** This project builds a GUI application using SwiftUI. Running it via `swift run` (or other methods) will launch this graphical interface, **not** a text-based command-line tool.

## Development Notes

*   File system access for the selected folder uses security-scoped bookmarks.
*   Interaction with LM Studio uses the `/v1/chat/completions` and `/v1/models` endpoints.
*   The LLM agent functionality involves parsing specific command formats from the LLM output and executing corresponding file system operations. 