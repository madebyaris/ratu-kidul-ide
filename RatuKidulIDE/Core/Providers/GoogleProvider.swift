import Foundation

/// Google (Gemini) AI Provider
actor GoogleProvider: AIProvider {
    let id = "google"
    let displayName = "Google"
    
    private let keychain: KeychainService
    
    init(keychain: KeychainService) {
        self.keychain = keychain
    }
    
    private func getBaseURL(modelId: String) -> URL {
        let model = modelId.replacingOccurrences(of: "google/", with: "")
        return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent")!
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
        guard let apiKey = try await keychain.get("google_api_key") else {
            throw ProviderError.missingAPIKey
        }
        
        var urlComponents = URLComponents(url: getBaseURL(modelId: config.modelId), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        var request = URLRequest(url: urlComponents.url!)
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
                let event = try JSONDecoder().decode(GoogleStreamEvent.self, from: data)
                if let candidates = event.candidates,
                   let first = candidates.first,
                   let content = first.content,
                   let parts = content.parts {
                    for part in parts {
                        if let text = part.text {
                            fullText += text
                            onChunk(text)
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        await onComplete(fullText, nil)
    }
    
    func validateAPIKey(_ key: String) async throws -> Bool {
        return !key.isEmpty && key.hasPrefix("AIza")
    }
    
    func listModels() async throws -> [Model] {
        return [
            Model(id: "google/gemini-pro", displayName: "Gemini Pro", isEnabled: true, supportedAttachmentTypes: [.text]),
            Model(id: "google/gemini-pro-vision", displayName: "Gemini Pro Vision", isEnabled: true, supportedAttachmentTypes: [.text, .image]),
            Model(id: "google/gemini-1.5-pro", displayName: "Gemini 1.5 Pro", isEnabled: true, supportedAttachmentTypes: [.text, .image])
        ]
    }
    
    private func buildRequestBody(
        config: ModelConfig,
        messages: [LLMMessage]
    ) throws -> GoogleRequest {
        let contents = messages.map { message -> GoogleRequest.Content in
            switch message {
            case .user(let content, _):
                return GoogleRequest.Content(role: "user", parts: [GoogleRequest.Part(text: content)])
            case .assistant(let content, _, _):
                return GoogleRequest.Content(role: "model", parts: [GoogleRequest.Part(text: content)])
            case .toolResults(let results):
                return GoogleRequest.Content(role: "user", parts: [GoogleRequest.Part(text: results.map { $0.content }.joined(separator: "\n"))])
            }
        }
        
        var request = GoogleRequest(contents: contents)
        
        if !config.systemPrompt.isEmpty {
            request.systemInstruction = GoogleRequest.Content(role: "user", parts: [GoogleRequest.Part(text: config.systemPrompt)])
        }
        
        return request
    }
}

// MARK: - Google API Types

struct GoogleRequest: Codable {
    var contents: [Content]
    var systemInstruction: Content?
    
    struct Content: Codable {
        let role: String
        let parts: [Part]
    }
    
    struct Part: Codable {
        let text: String
    }
}

struct GoogleStreamEvent: Codable {
    let candidates: [Candidate]?
    
    struct Candidate: Codable {
        let content: Content?
        
        struct Content: Codable {
            let parts: [Part]?
            
            struct Part: Codable {
                let text: String?
            }
        }
    }
}

