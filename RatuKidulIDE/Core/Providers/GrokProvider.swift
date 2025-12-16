import Foundation

/// Grok (xAI) Provider - Uses OpenAI-compatible API
actor GrokProvider: AIProvider {
    let id = "grok"
    let displayName = "Grok (xAI)"
    
    private let baseURL = URL(string: "https://api.x.ai/v1/chat/completions")!
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
        guard let apiKey = try await keychain.get("grok_api_key") else {
            throw ProviderError.missingAPIKey
        }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
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
        return !key.isEmpty
    }
    
    func listModels() async throws -> [Model] {
        return [
            Model(id: "grok/grok-beta", displayName: "Grok Beta", isEnabled: true, supportedAttachmentTypes: [.text])
        ]
    }
    
    private func buildRequestBody(
        config: ModelConfig,
        messages: [LLMMessage]
    ) throws -> GrokRequest {
        let modelId = config.modelId.replacingOccurrences(of: "grok/", with: "")
        
        var grokMessages: [GrokRequest.Message] = []
        
        if !config.systemPrompt.isEmpty {
            grokMessages.append(GrokRequest.Message(role: "system", content: config.systemPrompt))
        }
        
        for message in messages {
            switch message {
            case .user(let content, _):
                grokMessages.append(GrokRequest.Message(role: "user", content: content))
            case .assistant(let content, _, _):
                grokMessages.append(GrokRequest.Message(role: "assistant", content: content))
            case .toolResults(let results):
                grokMessages.append(GrokRequest.Message(role: "user", content: results.map { $0.content }.joined(separator: "\n")))
            }
        }
        
        return GrokRequest(model: modelId, messages: grokMessages, stream: true)
    }
}

// MARK: - Grok API Types

struct GrokRequest: Codable {
    let model: String
    let messages: [Message]
    let stream: Bool
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

