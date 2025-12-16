import Foundation

/// LM Studio Local Provider - Uses OpenAI-compatible API
actor LMStudioProvider: AIProvider {
    let id = "lmstudio"
    let displayName = "LM Studio"
    
    private let baseURL = URL(string: "http://localhost:1234/v1/chat/completions")!
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
        // LM Studio doesn't require an API key
        return true
    }
    
    func listModels() async throws -> [Model] {
        // Try to fetch models from LM Studio
        var request = URLRequest(url: URL(string: "http://localhost:1234/v1/models")!)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            
            let modelsResponse = try JSONDecoder().decode(LMStudioModelsResponse.self, from: data)
            return modelsResponse.data.map { model in
                Model(
                    id: "lmstudio::\(model.id)",
                    displayName: model.id,
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
    ) throws -> LMStudioRequest {
        // Extract model name: "lmstudio::model-name" → "model-name"
        let modelId = config.modelId.replacingOccurrences(of: "lmstudio::", with: "")
        
        var lmStudioMessages: [LMStudioRequest.Message] = []
        
        if !config.systemPrompt.isEmpty {
            lmStudioMessages.append(LMStudioRequest.Message(role: "system", content: config.systemPrompt))
        }
        
        for message in messages {
            switch message {
            case .user(let content, _):
                lmStudioMessages.append(LMStudioRequest.Message(role: "user", content: content))
            case .assistant(let content, _, _):
                lmStudioMessages.append(LMStudioRequest.Message(role: "assistant", content: content))
            case .toolResults(let results):
                lmStudioMessages.append(LMStudioRequest.Message(role: "user", content: results.map { $0.content }.joined(separator: "\n")))
            }
        }
        
        return LMStudioRequest(model: modelId, messages: lmStudioMessages, stream: true)
    }
}

// MARK: - LM Studio API Types

struct LMStudioRequest: Codable {
    let model: String
    let messages: [Message]
    let stream: Bool
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

struct LMStudioModelsResponse: Codable {
    let data: [LMStudioModel]
    
    struct LMStudioModel: Codable {
        let id: String
    }
}

