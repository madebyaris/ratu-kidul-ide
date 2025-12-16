import Foundation

/// Registry for routing model requests to the correct AI provider
@MainActor
final class ProviderRegistry {
    static let shared = ProviderRegistry()
    private let keychain = KeychainService.shared
    
    private init() {}
    
    /// Extracts the provider name from a model ID
    /// Examples:
    /// - "openai/gpt-4" → "openai"
    /// - "minimax/MiniMax-M2" → "minimax"
    /// - "openrouter::meta-llama/llama-4" → "openrouter"
    func getProviderName(for modelId: String) -> String {
        // Handle :: separator (used by some providers like openrouter, ollama)
        if modelId.contains("::") {
            return modelId.components(separatedBy: "::").first?.lowercased() ?? "openai"
        }
        // Handle / separator (standard format)
        return modelId.components(separatedBy: "/").first?.lowercased() ?? "openai"
    }
    
    /// Returns the appropriate provider for a given model ID
    func getProvider(for modelId: String) -> any AIProvider {
        let providerName = getProviderName(for: modelId)
        
        switch providerName {
        case "openai":
            return OpenAIProvider(keychain: keychain)
        case "openai-compatible":
            return OpenAIProvider(keychain: keychain) // Uses OpenAI format
        case "minimax":
            return MiniMaxProvider(keychain: keychain)
        case "anthropic":
            return AnthropicProvider(keychain: keychain)
        case "anthropic-compatible":
            return AnthropicProvider(keychain: keychain) // Uses Anthropic format
        case "google":
            return GoogleProvider(keychain: keychain)
        case "grok":
            return GrokProvider(keychain: keychain)
        case "openrouter":
            return OpenRouterProvider(keychain: keychain)
        case "perplexity":
            return PerplexityProvider(keychain: keychain)
        case "ollama":
            return OllamaProvider(keychain: keychain)
        case "lmstudio":
            return LMStudioProvider(keychain: keychain)
        default:
            // Fallback to OpenAI provider
            print("Unknown provider '\(providerName)', falling back to OpenAI")
            return OpenAIProvider(keychain: keychain)
        }
    }
    
    /// Streams a response using the appropriate provider for the model
    func streamResponse(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (String, [ToolCall]?) async -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        let provider = getProvider(for: config.modelId)
        
        try await provider.streamResponse(
            config: config,
            messages: messages,
            tools: tools,
            onChunk: onChunk,
            onToolCall: onToolCall,
            onComplete: onComplete,
            onError: onError
        )
    }
}

