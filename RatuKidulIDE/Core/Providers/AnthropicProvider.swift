import Foundation

/// Anthropic (Claude) AI Provider
actor AnthropicProvider: AIProvider {
    let id = "anthropic"
    let displayName = "Anthropic"
    
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
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
        guard let apiKey = try await keychain.get("anthropic_api_key") else {
            throw ProviderError.missingAPIKey
        }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body = try buildRequestBody(config: config, messages: messages, tools: tools)
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
        let toolCalls: [ToolCall] = [] // Not yet implemented for Anthropic
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            
            guard let data = jsonStr.data(using: .utf8) else { continue }
            
            do {
                let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
                
                switch event.type {
                case "content_block_delta":
                    if let delta = event.delta, let text = delta.text {
                        fullText += text
                        onChunk(text)
                    }
                case "message_stop":
                    await onComplete(fullText, toolCalls.isEmpty ? nil : toolCalls)
                    return
                default:
                    break
                }
            } catch {
                continue
            }
        }
        
        await onComplete(fullText, toolCalls.isEmpty ? nil : toolCalls)
    }
    
    func validateAPIKey(_ key: String) async throws -> Bool {
        return !key.isEmpty && key.hasPrefix("sk-ant-")
    }
    
    func listModels() async throws -> [Model] {
        return [
            Model(id: "anthropic/claude-3-5-sonnet-20241022", displayName: "Claude 3.5 Sonnet", isEnabled: true, supportedAttachmentTypes: [.text, .image]),
            Model(id: "anthropic/claude-3-opus-20240229", displayName: "Claude 3 Opus", isEnabled: true, supportedAttachmentTypes: [.text, .image]),
            Model(id: "anthropic/claude-3-haiku-20240307", displayName: "Claude 3 Haiku", isEnabled: true, supportedAttachmentTypes: [.text, .image])
        ]
    }
    
    private func buildRequestBody(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?
    ) throws -> AnthropicRequest {
        let modelId = config.modelId.replacingOccurrences(of: "anthropic/", with: "")
        
        let anthropicMessages = messages.compactMap { message -> AnthropicRequest.Message? in
            switch message {
            case .user(let content, _):
                return AnthropicRequest.Message(role: "user", content: content)
            case .assistant(let content, _, _):
                return AnthropicRequest.Message(role: "assistant", content: content)
            case .toolResults:
                return nil // Handle separately
            }
        }
        
        return AnthropicRequest(
            model: modelId,
            messages: anthropicMessages,
            maxTokens: 4096,
            stream: true,
            system: config.systemPrompt.isEmpty ? nil : config.systemPrompt
        )
    }
}

// MARK: - Anthropic API Types

struct AnthropicRequest: Codable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let stream: Bool
    let system: String?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, system
        case maxTokens = "max_tokens"
    }
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

struct AnthropicStreamEvent: Codable {
    let type: String
    let delta: Delta?
    
    struct Delta: Codable {
        let type: String?
        let text: String?
    }
}

