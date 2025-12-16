import Foundation

/// MiniMax AI Provider
/// API Documentation: https://platform.minimax.io/document/Chatcompletion_v2
actor MiniMaxProvider: AIProvider {
    let id = "minimax"
    let displayName = "MiniMax"
    
    private let baseURL = URL(string: "https://api.minimax.io/v1/")!
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
        guard let apiKey = try await keychain.get("minimax_api_key") else {
            throw ProviderError.missingAPIKey
        }
        
        // Construct the full endpoint URL
        let endpointURL = baseURL.appendingPathComponent("text/chatcompletion_v2")
        var request = URLRequest(url: endpointURL)
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
            // Try to read error message
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 1024 { break } // Limit error message size
            }
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("MiniMax API Error (\(httpResponse.statusCode)): \(errorMessage)")
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
                let event = try JSONDecoder().decode(MiniMaxStreamEvent.self, from: data)
                
                if let choice = event.choices.first {
                    if let delta = choice.delta {
                        // Handle content delta
                        if let content = delta.content {
                            fullText += content
                            onChunk(content)
                        }
                        
                        // Handle tool calls if present
                        if let deltaToolCalls = delta.toolCalls {
                            for toolCallDelta in deltaToolCalls {
                                if let index = toolCallDelta.index {
                                    while toolCalls.count <= index {
                                        toolCalls.append(ToolCall(
                                            id: UUID().uuidString,
                                            name: "",
                                            arguments: [:]
                                        ))
                                    }
                                    
                                    if let id = toolCallDelta.id, !id.isEmpty {
                                        toolCalls[index] = ToolCall(
                                            id: id,
                                            name: toolCallDelta.function?.name ?? toolCalls[index].name,
                                            arguments: toolCalls[index].arguments
                                        )
                                    }
                                    
                                    if let function = toolCallDelta.function, let name = function.name, !name.isEmpty {
                                        toolCalls[index] = ToolCall(
                                            id: toolCalls[index].id,
                                            name: name,
                                            arguments: toolCalls[index].arguments
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    if choice.finishReason == "tool_calls" {
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
        // MiniMax doesn't have a simple validation endpoint, so we'll just check format
        return !key.isEmpty && key.count > 10
    }
    
    func listModels() async throws -> [Model] {
        // Return known MiniMax models
        return [
            Model(
                id: "minimax/MiniMax-M1",
                displayName: "MiniMax M1",
                isEnabled: true,
                supportedAttachmentTypes: [.text]
            ),
            Model(
                id: "minimax/MiniMax-M2",
                displayName: "MiniMax M2",
                isEnabled: true,
                supportedAttachmentTypes: [.text, .image]
            )
        ]
    }
    
    private func buildRequestBody(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?
    ) throws -> MiniMaxRequest {
        // Extract model name from full ID (e.g., "minimax/MiniMax-M2" → "MiniMax-M2")
        let modelId = config.modelId.replacingOccurrences(of: "minimax/", with: "")
        
        let miniMaxMessages = messages.map { message -> MiniMaxRequest.Message in
            switch message {
            case .user(let content, _):
                return MiniMaxRequest.Message(role: "user", content: content)
            case .assistant(let content, _, _):
                return MiniMaxRequest.Message(role: "assistant", content: content)
            case .toolResults(let results):
                return MiniMaxRequest.Message(
                    role: "tool",
                    content: results.map { $0.content }.joined(separator: "\n")
                )
            }
        }
        
        var request = MiniMaxRequest(
            model: modelId,
            messages: miniMaxMessages,
            stream: true
        )
        
        // Add system prompt if present
        if !config.systemPrompt.isEmpty {
            request.messages.insert(
                MiniMaxRequest.Message(role: "system", content: config.systemPrompt),
                at: 0
            )
        }
        
        // Add tools if present
        if let tools = tools, !tools.isEmpty {
            request.tools = tools.map { tool in
                MiniMaxRequest.Tool(
                    type: "function",
                    function: MiniMaxRequest.Tool.FunctionDefinition(
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

// MARK: - MiniMax API Types

struct MiniMaxRequest: Codable {
    let model: String
    var messages: [Message]
    let stream: Bool
    var tools: [Tool]?
    
    struct Message: Codable {
        let role: String
        let content: String
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

struct MiniMaxStreamEvent: Codable {
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

