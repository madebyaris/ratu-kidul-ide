import Foundation

actor OpenAIProvider: AIProvider {
    let id = "openai"
    let displayName = "OpenAI"
    
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
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
        guard let apiKey = try await keychain.get("openai_api_key") else {
            throw ProviderError.missingAPIKey
        }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = try buildRequestBody(config: config, messages: messages, tools: tools)
        request.httpBody = try JSONEncoder().encode(body)
        
        // Use URLSession for streaming
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            onError(ProviderError.requestFailed)
            throw ProviderError.requestFailed
        }
        
        var fullText = ""
        var toolCalls: [ToolCall] = []
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            
            if jsonStr == "[DONE]" {
                await onComplete(fullText, toolCalls.isEmpty ? nil : toolCalls)
                return
            }
            
            guard let data = jsonStr.data(using: .utf8) else { continue }
            
            do {
                let event = try JSONDecoder().decode(OpenAIStreamEvent.self, from: data)
                
                if let choice = event.choices.first {
                    if let delta = choice.delta {
                        // Handle content delta
                        if let content = delta.content {
                            fullText += content
                            onChunk(content)
                        }
                        
                        // Handle tool calls
                        if let deltaToolCalls = delta.toolCalls {
                            for toolCallDelta in deltaToolCalls {
                                if let index = toolCallDelta.index {
                                    // Ensure we have enough tool calls
                                    while toolCalls.count <= index {
                                        toolCalls.append(ToolCall(
                                            id: UUID().uuidString,
                                            name: "",
                                            arguments: [:]
                                        ))
                                    }
                                    
                                    if let id = toolCallDelta.id {
                                        // New tool call
                                        if toolCalls[index].id.isEmpty {
                                            toolCalls[index] = ToolCall(
                                                id: id,
                                                name: toolCallDelta.function?.name ?? "",
                                                arguments: [:]
                                            )
                                        }
                                    }
                                    
                                    if let function = toolCallDelta.function {
                                        if let name = function.name, !name.isEmpty {
                                            toolCalls[index] = ToolCall(
                                                id: toolCalls[index].id,
                                                name: name,
                                                arguments: toolCalls[index].arguments
                                            )
                                        }
                                        
                                        if let argumentChunk = function.arguments {
                                            // Accumulate function arguments
                                            let currentArgs = toolCalls[index].arguments
                                            var newArgs = currentArgs
                                            
                                            // Parse JSON from argument chunk
                                            if let argData = argumentChunk.data(using: .utf8),
                                               let partialArgs = try? JSONDecoder().decode([String: AnyCodable].self, from: argData) {
                                                // Merge partial args
                                                for (key, value) in partialArgs {
                                                    newArgs[key] = value
                                                }
                                            }
                                            
                                            toolCalls[index] = ToolCall(
                                                id: toolCalls[index].id,
                                                name: toolCalls[index].name,
                                                arguments: newArgs
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if choice.finishReason == "tool_calls" {
                        // Filter out empty tool calls
                        let validToolCalls = toolCalls.filter { !$0.id.isEmpty && !$0.name.isEmpty }
                        await onComplete(fullText, validToolCalls.isEmpty ? nil : validToolCalls)
                        return
                    }
                }
            } catch {
                // Skip malformed events
                continue
            }
        }
        
        // Final completion
        await onComplete(fullText, toolCalls.isEmpty ? nil : toolCalls)
    }
    
    func validateAPIKey(_ key: String) async throws -> Bool {
        // Test with a simple models list request
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }
    
    func listModels() async throws -> [Model] {
        guard let apiKey = try await keychain.get("openai_api_key") else {
            return []
        }
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }
        
        let modelsResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return modelsResponse.data
            .filter { $0.id.hasPrefix("gpt") || $0.id.hasPrefix("o1") }
            .map { model in
                Model(
                    id: "openai/\(model.id)",
                    displayName: model.id,
                    isEnabled: true,
                    supportedAttachmentTypes: model.id.contains("vision") || model.id.contains("4") ? [.text, .image] : [.text]
                )
            }
    }
    
    private func buildRequestBody(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?
    ) throws -> OpenAIRequest {
        let modelId = config.modelId.replacingOccurrences(of: "openai/", with: "")
        
        let openAIMessages = messages.map { message -> OpenAIRequest.Message in
            switch message {
            case .user(let content, let attachments):
                if attachments.isEmpty {
                    return OpenAIRequest.Message(role: "user", content: .string(content))
                } else {
                    var contentArray: [OpenAIRequest.Content] = [.string(content)]
                    for attachment in attachments {
                        if attachment.type == .image {
                            // For images, we'd need to encode as base64
                            // Simplified for now
                            contentArray.append(.string("[Image: \(attachment.originalName ?? "image")]"))
                        }
                    }
                    return OpenAIRequest.Message(role: "user", content: .array(contentArray))
                }
            case .assistant(let content, _, let toolCalls):
                var message = OpenAIRequest.Message(role: "assistant", content: .string(content))
                if !toolCalls.isEmpty {
                    message.toolCalls = toolCalls.map { toolCall in
                        let argsDict = toolCall.arguments.mapValues { $0.value }
                        let argsJSON = try! JSONSerialization.data(withJSONObject: argsDict)
                        let argsString = String(data: argsJSON, encoding: .utf8) ?? "{}"
                        
                        return OpenAIRequest.ToolCall(
                            id: toolCall.id,
                            type: "function",
                            function: OpenAIRequest.ToolCall.Function(
                                name: toolCall.name,
                                arguments: argsString
                            )
                        )
                    }
                }
                return message
            case .toolResults(let results):
                return OpenAIRequest.Message(
                    role: "tool",
                    content: .string(results.map { $0.content }.joined(separator: "\n"))
                )
            }
        }
        
        var request = OpenAIRequest(
            model: modelId,
            messages: openAIMessages,
            stream: true
        )
        
        if !config.systemPrompt.isEmpty {
            request.messages.insert(
                OpenAIRequest.Message(role: "system", content: .string(config.systemPrompt)),
                at: 0
            )
        }
        
        if let tools = tools, !tools.isEmpty {
            request.tools = tools.map { tool in
                OpenAIRequest.Tool(
                    type: "function",
                    function: OpenAIRequest.Tool.FunctionDefinition(
                        name: tool.namespacedName,
                        description: tool.description ?? "",
                        parameters: tool.inputSchema
                    )
                )
            }
        }
        
        return request
    }
}

// MARK: - OpenAI API Types

struct OpenAIRequest: Codable {
    let model: String
    var messages: [Message]
    let stream: Bool
    var tools: [Tool]?
    
    struct Message: Codable {
        let role: String
        let content: Content
        var toolCalls: [ToolCall]?
        
        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
        }
    }
    
    enum Content: Codable {
        case string(String)
        case array([Content])
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let array = try? container.decode([Content].self) {
                self = .array(array)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid content")
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string):
                try container.encode(string)
            case .array(let array):
                try container.encode(array)
            }
        }
    }
    
    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: Function
        
        struct Function: Codable {
            let name: String
            let arguments: String
        }
    }
    
    struct Tool: Codable {
        let type: String
        let function: FunctionDefinition
        
        struct FunctionDefinition: Codable {
            let name: String
            let description: String
            let parameters: [String: AnyCodable]
        }
    }
}

struct OpenAIStreamEvent: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let delta: Delta?
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
        
        struct Delta: Codable {
            let content: String?
            let toolCalls: [ToolCallDelta]?
            
            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
            
            struct ToolCallDelta: Codable {
                let index: Int?
                let id: String?
                let type: String?
                let function: FunctionDelta?
                
                struct FunctionDelta: Codable {
                    let name: String?
                    let arguments: String?
                }
            }
        }
    }
}

struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
    
    struct OpenAIModel: Codable {
        let id: String
    }
}

// Helper extension for collecting async bytes
extension Data {
    static func collecting<T: AsyncSequence>(_ sequence: T, upTo limit: Int) async throws -> Data where T.Element == UInt8 {
        var data = Data()
        var count = 0
        for try await byte in sequence {
            data.append(byte)
            count += 1
            if count >= limit {
                break
            }
        }
        return data
    }
}

