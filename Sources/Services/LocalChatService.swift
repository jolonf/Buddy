import Foundation
import SwiftUI
import MLX
import MLXLMCommon
import MLXLLM
import Hub

#if os(macOS)
extension HubApi: @retroactive @unchecked Sendable {
    /// Default HubApi instance configured to download models to the user's Downloads directory under a 'huggingface' subdirectory.
    static var `default`: HubApi {
        // This getter is @MainActor, so access is safe
        // swiftlint:disable:next actor_isolation
        @MainActor get {
            HubApi(
                downloadBase: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("huggingface", isDirectory: true)
            )
        }
    }
}
#endif

class LocalChatService: ChatService, @unchecked Sendable {

    private var currentModelContainer: ModelContainer?
    private var currentModelId: String?
    private var currentPromptCache: PromptCache?
    private var generationTask: Task<Void, Never>?

    init() {
        print("LocalChatService initialized.")
    }

    func fetchAvailableModels() async throws -> [CombinedModelInfo] {
        print("DEBUG: fetchAvailableModels() called in LocalChatService")
        
        let fileManager = FileManager.default
        guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            print("Error: Could not find Downloads directory.")
            return []
        }
        
        let huggingFaceDirURL = downloadsURL.appendingPathComponent("huggingface", isDirectory: true)
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: huggingFaceDirURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            print("Local models directory not found or is not a directory: \(huggingFaceDirURL.path)")
            return []
        }
        
        var discoveredModels: [CombinedModelInfo] = []
        
        func findModels(in directoryURL: URL, basePath: String, fileManager: FileManager, discoveredModels: inout [CombinedModelInfo]) async throws {
            let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            
            for itemURL in contents {
                var itemIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &itemIsDirectory), itemIsDirectory.boolValue else {
                    continue
                }
                
                let itemName = itemURL.lastPathComponent
                let currentRelativePath = basePath.isEmpty ? itemName : "\(basePath)/\(itemName)"

                if await isPotentialModelDirectory(url: itemURL, fileManager: fileManager) {
                    discoveredModels.append(CombinedModelInfo(id: currentRelativePath, displayName: itemName, type: .local))
                } else if basePath.isEmpty {
                    let subContents = try fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                    for subItemURL in subContents {
                        var subItemIsDirectory: ObjCBool = false
                        guard fileManager.fileExists(atPath: subItemURL.path, isDirectory: &subItemIsDirectory), subItemIsDirectory.boolValue else {
                            continue
                        }
                        let subItemName = subItemURL.lastPathComponent
                        let subItemRelativePath = "\(currentRelativePath)/\(subItemName)"
                        if await isPotentialModelDirectory(url: subItemURL, fileManager: fileManager) {
                            discoveredModels.append(CombinedModelInfo(id: subItemRelativePath, displayName: subItemName, type: .local))
                        }
                    }
                }
            }
        }

        do {
            try await findModels(in: huggingFaceDirURL, basePath: "", fileManager: fileManager, discoveredModels: &discoveredModels)
        } catch {
            print("Error scanning for local models: \(error)")
            throw error
        }
        
        print("Discovered local models: \(discoveredModels.map { $0.displayName })")
        let uniqueModels = Array(Set(discoveredModels))
        return uniqueModels.sorted { $0.displayName < $1.displayName }
    }

    func sendMessage(
        history: [ChatMessage],
        systemPrompt: String,
        model: CombinedModelInfo,
        interactionMode: InteractionMode
    ) -> AsyncThrowingStream<ChatStreamUpdate, Error> {
        print("DEBUG: sendMessage() called in LocalChatService for model \(model.displayName)")
        
        guard let container = currentModelContainer, model.id == currentModelId else {
            let error = NSError(domain: "LocalChatService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Model \(model.displayName) is not loaded or does not match the current loaded model."])
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        
        return AsyncThrowingStream(ChatStreamUpdate.self, bufferingPolicy: .unbounded) { continuation in
            self.generationTask = Task {
                do {
                    var mlxMessages: [Chat.Message] = []
                    if !systemPrompt.isEmpty {
                        mlxMessages.append(Chat.Message(role: .system, content: systemPrompt))
                    }
                    for messageItem in history {
                        let role: Chat.Message.Role
                        switch messageItem.role {
                        case .user: role = .user
                        case .assistant: role = .assistant
                        case .system: role = .system
                        }
                        mlxMessages.append(Chat.Message(role: role, content: messageItem.content))
                    }
                    let userInput = UserInput(chat: mlxMessages)

                    let generationStreamResult: AsyncStream<Generation> = try await container.perform { (context: ModelContext) -> AsyncStream<Generation> in
                        if self.currentPromptCache == nil {
                            print("PromptCache was nil, initializing inside perform for model \(self.currentModelId ?? "unknown").")
                            self.currentPromptCache = PromptCache(cache: context.model.newCache(parameters: GenerateParameters()))
                        }
                        guard let cacheForThisGeneration = self.currentPromptCache else {
                            throw NSError(domain: "LocalChatService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Prompt cache is unexpectedly nil after attempted initialization."])
                        }
                        let fullPromptLmInput = try await context.processor.prepare(input: userInput)
                        let parameters = GenerateParameters(temperature: 0.7)
                        var lmInputForGeneration: LMInput
                        var kvCachesForGeneration: [KVCache]
                        if let suffixTokens = cacheForThisGeneration.getUncachedSuffix(prompt: fullPromptLmInput.text.tokens) {
                            print("Using prompt cache. Suffix size: \(suffixTokens.size)")
                            lmInputForGeneration = LMInput(text: LMInput.Text(tokens: suffixTokens))
                            kvCachesForGeneration = cacheForThisGeneration.cache
                        } else {
                            print("Prompt cache inconsistent. Creating new cache.")
                            let newCacheInstance = PromptCache(cache: context.model.newCache(parameters: parameters))
                            self.currentPromptCache = newCacheInstance
                            lmInputForGeneration = fullPromptLmInput
                            kvCachesForGeneration = newCacheInstance.cache
                        }
                        return try MLXLMCommon.generate(
                            input: lmInputForGeneration,
                            parameters: parameters,
                            context: context,
                            cache: kvCachesForGeneration
                        )
                    }
                    
                    for try await generationUpdate in generationStreamResult {
                        if Task.isCancelled {
                            print("LocalChatService generation task cancelled during streaming.")
                            continuation.finish()
                            return
                        }
                        
                        switch generationUpdate {
                        case .chunk(let textDelta):
                            continuation.yield(.contentDelta(textDelta))
                        
                        case .info(let completionInfo):
                            let usageMetrics = ChatUsageMetrics(
                                prompt_tokens: completionInfo.promptTokenCount,
                                completion_tokens: completionInfo.generationTokenCount,
                                total_tokens: completionInfo.promptTokenCount + completionInfo.generationTokenCount,
                                prompt_time: completionInfo.promptTime,
                                generation_time: completionInfo.generateTime
                            )
                            continuation.yield(.usage(usageMetrics))
                        }
                    }
                    continuation.finish()

                } catch {
                    if Task.isCancelled && error is CancellationError {
                        print("LocalChatService Task was cancelled before or during generation setup.")
                        continuation.finish()
                    } else {
                        print("Error in LocalChatService sendMessage task: \(error)")
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                print("AsyncThrowingStream terminated. Cancelling associated generation task.")
                Task {
                    self.doCancelGenerationTask()
                }
            }
        }
    }

    private func doCancelGenerationTask() {
        self.generationTask?.cancel()
        self.generationTask = nil
    }

    func cancelCurrentRequest() {
        print("DEBUG: cancelCurrentRequest() called in LocalChatService")
        Task {
            doCancelGenerationTask()
        }
    }

    func loadLocalModel(_ modelInfo: CombinedModelInfo) async throws {
        print("DEBUG: loadLocalModel() called in LocalChatService for model \(modelInfo.displayName)")

        if currentModelContainer != nil {
            await unloadLocalModel()
        }
        
        do {
            let fileManager = FileManager.default
            guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "LocalChatService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Could not find Downloads directory."])
            }
            let huggingFaceDirURL = downloadsURL.appendingPathComponent("huggingface", isDirectory: true)
            let modelDirectoryURL = huggingFaceDirURL.appendingPathComponent(modelInfo.id, isDirectory: true)
            let config = ModelConfiguration(directory: modelDirectoryURL)
            print("Attempting to load model with directory: \(modelDirectoryURL.path) using ModelConfiguration.")
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            // Use MainActor to access HubApi.default safely
            let hubApi = await MainActor.run { HubApi.default }
            let container = try await LLMModelFactory.shared.loadContainer(
                hub: hubApi,
                configuration: config
            )
            
            self.currentModelContainer = container
            self.currentModelId = modelInfo.id
            
            if let promptCache = await container.perform({ (ctx: ModelContext) -> PromptCache? in
                // ModelContext is not Sendable, so do all work inside this closure
                PromptCache(cache: ctx.model.newCache(parameters: GenerateParameters()))
            }) {
                self.currentPromptCache = promptCache
                print("PromptCache initialized after loading model \(modelInfo.displayName).")
            } else {
                self.currentPromptCache = nil
                print("Warning: Could not get model context to initialize prompt cache for \(modelInfo.displayName). It will be created on first sendMessage.")
            }

            print("Successfully loaded local model: \(modelInfo.displayName)")
        } catch {
            print("Error loading local model \(modelInfo.displayName): \(error)")
            self.currentModelContainer = nil
            self.currentModelId = nil
            self.currentPromptCache = nil
            throw error
        }
    }

    func unloadLocalModel() async {
        print("DEBUG: unloadLocalModel() called in LocalChatService for model \(currentModelId ?? "unknown")")
        doCancelGenerationTask()
        currentModelContainer = nil
        currentModelId = nil
        currentPromptCache = nil
        print("Local model unloaded.")
    }
    
    private func isPotentialModelDirectory(url: URL, fileManager: FileManager) async -> Bool {
        let configJsonExists = fileManager.fileExists(atPath: url.appendingPathComponent("config.json").path)
        let tokenizerJsonExists = fileManager.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path)
        var safetensorsExist = false
        do {
            let directoryContents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            safetensorsExist = directoryContents.contains { $0.pathExtension == "safetensors" }
        } catch {
            print("Error reading directory contents for \(url.path) to check for .safetensors: \(error)")
            return false
        }
        return configJsonExists && tokenizerJsonExists && safetensorsExist
    }
}
