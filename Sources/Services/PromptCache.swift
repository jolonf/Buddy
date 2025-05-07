//
//  PromptCache.swift
//  mlx-swift-examples // Or adjust if this comment should reflect "Buddy"
//
//  Created by Jolon Faichney on 3/5/2025.
//

import MLX
import MLXLMCommon

/// Stores the KV Cache between calls to ``generate`` and maintains
/// the token ids reflected in the cache.
///
/// ``PromptCache`` is ``@unchecked Sendable`` which allows it
/// to be used within the ``ModelContainer`` context.
///
/// TODO: cache isolation
public class PromptCache: @unchecked Sendable {
    private(set) var cache: [KVCache]
    private(set) var tokens: MLXArray

    public init(cache: [KVCache]) {
        print("[PromptCache.init]")
        self.cache = cache
        // REVERT: Initialize tokens as an empty Swift array, as in the MLXChatExample
        self.tokens = []
    }

    /// Returns the suffix of the prompt not already in cache, so that only
    /// the new part is processed. The tokens of the cache are adjusted here
    /// to reflect the new full prompt (i.e. the suffix tokens are added to the
    /// cache tokens array), assuming that the prompt suffix will
    /// be processed after the call to this function.
    ///
    /// Trims cache if necessary if part of the cache doesn't match the new
    /// prompt. If the model doesn't support trimming and the cache needs to be
    /// trimmed, will return nil for the caller to create a new cache.
    ///
    /// - Returns:
    ///     - If entirety of cache is in the new prompt:
    ///         - Return suffix of new prompt, less what is in the cache
    ///     - If only a portion of the cache is in the new prompt:
    ///         - Attempt to trim the cache to the common prefix
    ///         - Return suffix of prompt not in cache
    ///         - If the cache is not trimmable return nil for the caller
    ///             to create a new cache.
    public func getUncachedSuffix(prompt: MLXArray) -> MLXArray? {

        print("[getUncachedSuffix] self.tokens.size = \(self.tokens.size)")

        print("cache[\(self.tokens.size)]: \(self.tokens)")
        print("prompt[\(prompt.size)]: \(prompt)")

        let comPrefixLength = commonPrefixLength(newPromptTokens: prompt)
        print("[getUncachedSuffix] comPrefixLength: \(comPrefixLength)")

        if comPrefixLength == self.tokens.size {
            let suffix = prompt[comPrefixLength ..< prompt.size]
            // REVERT: Use .size for checks
            if self.tokens.size == 0 && suffix.size > 0 {
                self.tokens = suffix
            } else if suffix.size > 0 {
                self.tokens = concatenated([self.tokens, suffix], axis: 0)
            }
            return suffix
        } else if comPrefixLength < self.tokens.size {
            if isTrimmable() {
                print("trimming: \(self.tokens.size - comPrefixLength)")
                let trimmedCount = self.trim(self.tokens.size - comPrefixLength)
                print("trimmed by: \(trimmedCount)")
                self.tokens = self.tokens[0 ..< comPrefixLength]
                
                let suffix = prompt[comPrefixLength ..< prompt.size]
                // REVERT: Use .size for checks
                if self.tokens.size == 0 && suffix.size > 0 {
                     self.tokens = suffix
                } else if suffix.size > 0 {
                     self.tokens = concatenated([self.tokens, suffix], axis: 0)
                }
                return suffix
            } else {
                print("[getUncachedSuffix] Cache not trimmable and needs trimming. Returning nil.")
                return nil
            }
        } else if comPrefixLength > self.tokens.size {
            print("[getUncachedSuffix] Error: Common prefix longer than current cache tokens. Cache might be inconsistent.")
            return nil
        }

        // REVERT: Use .size for checks
        if self.tokens.size == 0 && comPrefixLength == 0 {
            self.tokens = prompt
            return prompt
        }
        
        print("[getUncachedSuffix] Unhandled case or no uncached suffix (e.g. prompt is identical to cache or fully new).")
        return nil
    }

    /// - Returns: true if all KV caches are trimmable
    public func isTrimmable() -> Bool {
        return cache.allSatisfy { $0.isTrimmable() }
    }

    /// Trims all KV caches.
    /// - Parameters:
    ///   - n: Amount to trim.
    /// - Returns: Amount KV Caches were trimmed (may be less than ``n``).
    public func trim(_ n: Int) -> Int {
        if !self.isTrimmable() {
            return 0
        }
        var minTrimmed = n
        if cache.isEmpty { return 0 }

        for kv_cache_layer in cache {
            let trimmedInLayer = kv_cache_layer.trim(n: n)
            minTrimmed = min(minTrimmed, trimmedInLayer)
        }
        return minTrimmed
    }

    /// Finds the common prefix between the cached prompt and
    /// the new prompt.
    /// - Parameters:
    ///   - newPromptTokens: Tokens to compare with cached tokens.
    /// - Returns: Length of the common prefix
    public func commonPrefixLength(newPromptTokens: MLXArray) -> Int {
        return commonPrefixLength(self.tokens, newPromptTokens)
    }

    /// Finds the common prefix between ``MLXArray``s.
    /// - Parameters:
    ///   - array1: First array
    ///   - array2: Second array
    /// - Returns: Length of the common prefix
    public func commonPrefixLength(_ array1: MLXArray, _ array2: MLXArray) -> Int {
        // REVERT: to MLXChatExample's implementation for dtype-agnostic comparison
        // print("Calculating common prefix: array1[\(array1.size)] array2[\(array2.size)]") // Optional: for debugging
        if array1.size == 0 || array2.size == 0 { // Keep this basic check for empty arrays
            return 0
        }
        let minLength = min(array1.size, array2.size)
        // if minLength == 0 { return 0 } // Redundant if above check is present

        for i in 0 ..< minLength {
            // Use MLX 'all' and '!=' for element-wise comparison, then get scalar Bool
            if all(array1[i] .!= array2[i]).item(Bool.self) {
                 return i
            }
        }
        return minLength
    }
}
