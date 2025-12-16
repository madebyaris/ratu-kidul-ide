import Foundation

/// Ollama Local Provider
actor OllamaProvider: AIProvider {
    let id = "ollama"
    let displayName = "Ollama"
    
    private let baseURL = URL(string: "http://localhost:11434/api/chat")!
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
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
            guard let data = line.data(using: .utf8) else { continue }
            
            do {
                let event = try JSONDecoder().decode(OllamaStreamEvent.self, from: data)
                if let content = event.message?.content {
                    fullText += content
                    onChunk(content)
                }
                if event.done == true {
                    await onComplete(fullText, nil)
                    return
                }
            } catch {
                continue
            }
        }
        
        await onComplete(fullText, nil)
    }
    
    func validateAPIKey(_ key: String) async throws -> Bool {
        // Ollama doesn't require an API key
        return true
    }
    
    func listModels() async throws -> [Model] {
        // Try to fetch models from Ollama
        var request = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            
            let modelsResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
            return modelsResponse.models.map { model in
                Model(
                    id: "ollama::\(model.name)",
                    displayName: model.name,
                    isEnabled: true,
                    supportedAttachmentTypes: [.text]
                )
            }
        } catch {
            return []
        }
    }
    
    private func buildRequestBody(
        config: ModelConfig,
        messages: [LLMMessage]
    ) throws -> OllamaRequest {
        // Extract model name: "ollama::llama2" → "llama2"
        let modelId = config.modelId.replacingOccurrences(of: "ollama::", with: "")
        
        var ollamaMessages: [OllamaRequest.Message] = []
        
        if !config.systemPrompt.isEmpty {
            ollamaMessages.append(OllamaRequest.Message(role: "system", content: config.systemPrompt))
        }
        
        for message in messages {
            switch message {
            case .user(let content, _):
                ollamaMessages.append(OllamaRequest.Message(role: "user", content: content))
            case .assistant(let content, _, _):
                ollamaMessages.append(OllamaRequest.Message(role: "assistant", content: content))
            case .toolResults(let results):
                ollamaMessages.append(OllamaRequest.Message(role: "user", content: results.map { $0.content }.joined(separator: "\n")))
            }
        }
        
        return OllamaRequest(model: modelId, messages: ollamaMessages, stream: true)
    }
}

// MARK: - Ollama API Types

struct OllamaRequest: Codable {
    let model: String
    let messages: [Message]
    let stream: Bool
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

struct OllamaStreamEvent: Codable {
    let message: Message?
    let done: Bool?
    
    struct Message: Codable {
        let content: String?
    }
}

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
    
    struct OllamaModel: Codable {
        let name: String
    }
}

