import Foundation

/// OpenRouter Provider - Routes to various models via OpenRouter API
actor OpenRouterProvider: AIProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"
    
    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let keychain: KeychainService
    
    init(keychain: KeychainService) {
        self.keychain = keychain
    }
    
    func streamResponse(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (String, [ToolCall]?) async -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        guard let apiKey = try await keychain.get("openrouter_api_key") else {
            throw ProviderError.missingAPIKey
        }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://ratukidul.sh", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Ratu Kidul IDE", forHTTPHeaderField: "X-Title")
        
        let body = try buildRequestBody(config: config, messages: messages)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            onError(ProviderError.requestFailed)
            throw ProviderError.requestFailed
        }
        
        var fullText = ""
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            
            if jsonStr == "[DONE]" {
                await onComplete(fullText, nil)
                return
            }
            
            guard let data = jsonStr.data(using: .utf8) else { continue }
            
            do {
                let event = try JSONDecoder().decode(OpenAIStreamEvent.self, from: data)
                if let choice = event.choices.first, let delta = choice.delta, let content = delta.content {
                    fullText += content
                    onChunk(content)
                }
            } catch {
                continue
            }
        }
        
        await onComplete(fullText, nil)
    }
    
    func validateAPIKey(_ key: String) async throws -> Bool {
        return !key.isEmpty && key.hasPrefix("sk-or-")
    }
    
    func listModels() async throws -> [Model] {
        return [
            Model(id: "openrouter::meta-llama/llama-3.1-70b-instruct", displayName: "Llama 3.1 70B", isEnabled: true, supportedAttachmentTypes: [.text]),
            Model(id: "openrouter::anthropic/claude-3.5-sonnet", displayName: "Claude 3.5 Sonnet (OpenRouter)", isEnabled: true, supportedAttachmentTypes: [.text, .image])
        ]
    }
    
    private func buildRequestBody(
        config: ModelConfig,
        messages: [LLMMessage]
    ) throws -> OpenRouterRequest {
        // Extract model ID: "openrouter::meta-llama/llama-3.1-70b" → "meta-llama/llama-3.1-70b"
        let modelId = config.modelId.replacingOccurrences(of: "openrouter::", with: "")
        
        var openRouterMessages: [OpenRouterRequest.Message] = []
        
        if !config.systemPrompt.isEmpty {
            openRouterMessages.append(OpenRouterRequest.Message(role: "system", content: config.systemPrompt))
        }
        
        for message in messages {
            switch message {
            case .user(let content, _):
                openRouterMessages.append(OpenRouterRequest.Message(role: "user", content: content))
            case .assistant(let content, _, _):
                openRouterMessages.append(OpenRouterRequest.Message(role: "assistant", content: content))
            case .toolResults(let results):
                openRouterMessages.append(OpenRouterRequest.Message(role: "user", content: results.map { $0.content }.joined(separator: "\n")))
            }
        }
        
        return OpenRouterRequest(model: modelId, messages: openRouterMessages, stream: true)
    }
}

// MARK: - OpenRouter API Types

struct OpenRouterRequest: Codable {
    let model: String
    let messages: [Message]
    let stream: Bool
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

