import Foundation

/// Anthropic (Claude) AI Provider
actor AnthropicProvider: AIProvider {
    let id = "anthropic"
    let displayName = "Anthropic"
    
    private let defaultBaseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let keychain: KeychainService
    
    init(keychain: KeychainService) {
        self.keychain = keychain
    }
    
    /// Get the appropriate API URL for the config
    private func getAPIURL(for config: ModelConfig) -> URL {
        // If custom base URL is set, use it (don't modify it)
        if let customURL = config.customBaseURL, !customURL.isEmpty {
            // Append /messages if the URL doesn't already have it
            var urlString = customURL
            if !urlString.hasSuffix("/messages") {
                if !urlString.hasSuffix("/") {
                    urlString += "/"
                }
                urlString += "messages"
            }
            return URL(string: urlString) ?? defaultBaseURL
        }
        return defaultBaseURL
    }
    
    /// Get the appropriate keychain key for the config
    private func getKeychainKey(for config: ModelConfig) -> String {
        let modelId = config.modelId.lowercased()
        if modelId.hasPrefix("anthropic-compatible/") {
            return "anthropic_compatible_api_key"
        }
        return "anthropic_api_key"
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
        let keychainKey = getKeychainKey(for: config)
        guard let apiKey = try await keychain.get(keychainKey) else {
            throw ProviderError.missingAPIKey
        }
        
        let apiURL = getAPIURL(for: config)
        var request = URLRequest(url: apiURL)
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
        var toolCalls: [ToolCall] = []
        var toolCallPartialJSON: [String: String] = [:] // Track partial JSON per tool ID
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            
            // Skip empty lines and [DONE] marker
            if jsonStr.isEmpty || jsonStr == "[DONE]" {
                continue
            }
            
            guard let data = jsonStr.data(using: .utf8) else { continue }
            
            do {
                let decoder = JSONDecoder()
                let event = try decoder.decode(AnthropicStreamEvent.self, from: data)
                
                switch event.type {
                case "content_block_start":
                    // Tool use block started
                    if let contentBlock = event.contentBlock,
                       contentBlock.type == "tool_use",
                       let toolId = contentBlock.toolUse?.id,
                       let toolName = contentBlock.toolUse?.name {
                        // Create new tool call
                        let newToolCall = ToolCall(
                            id: toolId,
                            name: toolName,
                            arguments: [:]
                        )
                        toolCalls.append(newToolCall)
                        toolCallPartialJSON[toolId] = "" // Initialize partial JSON accumulator
                        print("🔧 [AnthropicProvider] Tool call started: \(toolName) (id: \(toolId))")
                        onToolCall(newToolCall) // Notify immediately
                    }
                    
                case "content_block_delta":
                    if let delta = event.delta {
                        // Handle text content delta
                        if let text = delta.text {
                            fullText += text
                            onChunk(text)
                        }
                        
                        // Handle tool use delta - arguments streamed as partial JSON
                        if delta.type == "input_json_delta",
                           let partialJSON = delta.partialJSON {
                            // Find the current tool call by index
                            if let index = event.index,
                               index < toolCalls.count {
                                let toolId = toolCalls[index].id
                                // Accumulate partial JSON
                                toolCallPartialJSON[toolId, default: ""] += partialJSON
                            }
                        }
                    }
                    
                case "content_block_stop":
                    // Finalize tool call arguments when block stops
                    if let index = event.index,
                       index < toolCalls.count {
                        let toolId = toolCalls[index].id
                        if let accumulatedJSON = toolCallPartialJSON[toolId],
                           !accumulatedJSON.isEmpty {
                            // Try to parse the complete JSON
                            if let jsonData = accumulatedJSON.data(using: .utf8),
                               let args = try? decoder.decode([String: AnyCodable].self, from: jsonData) {
                                toolCalls[index] = ToolCall(
                                    id: toolCalls[index].id,
                                    name: toolCalls[index].name,
                                    arguments: args
                                )
                                print("✅ [AnthropicProvider] Parsed arguments for \(toolCalls[index].name): \(args.count) params")
                            } else {
                                print("⚠️ [AnthropicProvider] Failed to parse JSON for \(toolCalls[index].name): \(accumulatedJSON)")
                            }
                            toolCallPartialJSON.removeValue(forKey: toolId)
                        }
                    }
                    
                case "message_stop":
                    // Finalize any pending tool calls
                    let validToolCalls = toolCalls.filter { !$0.id.isEmpty && !$0.name.isEmpty }
                    
                    if !validToolCalls.isEmpty {
                        print("🔧 [AnthropicProvider] Tool calls completed:")
                        for (idx, call) in validToolCalls.enumerated() {
                            print("   [\(idx)] \(call.name) (id: \(call.id))")
                            print("      Arguments (\(call.arguments.count)):")
                            for (key, value) in call.arguments {
                                print("         \(key): \(value.value)")
                            }
                        }
                    }
                    
                    await onComplete(fullText, validToolCalls.isEmpty ? nil : validToolCalls)
                    return
                    
                default:
                    break
                }
            } catch {
                // Skip malformed events
                print("⚠️ [AnthropicProvider] Failed to parse event: \(error)")
                if let jsonStr = String(data: data, encoding: .utf8) {
                    print("   Raw event: \(jsonStr)")
                }
                continue
            }
        }
        
        // Final completion
        let validToolCalls = toolCalls.filter { !$0.id.isEmpty && !$0.name.isEmpty }
        await onComplete(fullText, validToolCalls.isEmpty ? nil : validToolCalls)
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
        // Remove provider prefix from model ID
        var modelId = config.modelId
        modelId = modelId.replacingOccurrences(of: "anthropic/", with: "")
        modelId = modelId.replacingOccurrences(of: "anthropic-compatible/", with: "")
        
        // Convert messages to Anthropic format with content blocks
        var anthropicMessages: [AnthropicRequest.Message] = []
        
        for message in messages {
            switch message {
            case .user(let content, _):
                // User messages: content is array of text blocks
                anthropicMessages.append(AnthropicRequest.Message(
                    role: "user",
                    content: [.text(content)]
                ))
                
            case .assistant(let content, _, let toolCalls):
                // Assistant messages: can have text and/or tool_use blocks
                var contentBlocks: [AnthropicRequest.Message.ContentBlock] = []
                
                // Add text content if present
                if !content.isEmpty {
                    contentBlocks.append(.text(content))
                }
                
                // Add tool_use blocks if present
                for toolCall in toolCalls {
                    contentBlocks.append(.toolUse(AnthropicRequest.Message.ContentBlock.ToolUse(
                        id: toolCall.id,
                        name: toolCall.name,
                        input: toolCall.arguments
                    )))
                }
                
                anthropicMessages.append(AnthropicRequest.Message(
                    role: "assistant",
                    content: contentBlocks
                ))
                
            case .toolResults(let results):
                // Tool results: Anthropic sends these as user messages with tool_result blocks
                var contentBlocks: [AnthropicRequest.Message.ContentBlock] = []
                for result in results {
                    contentBlocks.append(.toolResult(AnthropicRequest.Message.ContentBlock.ToolResult(
                        toolUseId: result.id,
                        content: result.content
                    )))
                }
                anthropicMessages.append(AnthropicRequest.Message(
                    role: "user",
                    content: contentBlocks
                ))
            }
        }
        
        // Convert tools to Anthropic format if present
        let anthropicTools: [AnthropicRequest.Tool]? = tools?.map { tool in
            AnthropicRequest.Tool(
                name: tool.namespacedName,
                description: tool.description ?? "",
                inputSchema: tool.inputSchema
            )
        }
        
        return AnthropicRequest(
            model: modelId,
            messages: anthropicMessages,
            maxTokens: 4096,
            stream: true,
            system: config.systemPrompt.isEmpty ? nil : config.systemPrompt,
            tools: anthropicTools
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
    let tools: [Tool]?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, system, tools
        case maxTokens = "max_tokens"
    }
    
    struct Message: Codable {
        let role: String
        let content: [ContentBlock]
        
        enum ContentBlock: Codable {
            case text(String)
            case toolUse(ToolUse)
            case toolResult(ToolResult)
            
            enum CodingKeys: String, CodingKey {
                case type, text, id, name, input, toolUseId = "tool_use_id", content
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(String.self, forKey: .type)
                
                switch type {
                case "text":
                    self = .text(try container.decode(String.self, forKey: .text))
                case "tool_use":
                    let id = try container.decode(String.self, forKey: .id)
                    let name = try container.decode(String.self, forKey: .name)
                    let input = try container.decode([String: AnyCodable].self, forKey: .input)
                    self = .toolUse(ToolUse(id: id, name: name, input: input))
                case "tool_result":
                    let toolUseId = try container.decode(String.self, forKey: .toolUseId)
                    let content = try container.decode(String.self, forKey: .content)
                    self = .toolResult(ToolResult(toolUseId: toolUseId, content: content))
                default:
                    throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content block type: \(type)")
                }
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .toolUse(let toolUse):
                    try container.encode("tool_use", forKey: .type)
                    try container.encode(toolUse.id, forKey: .id)
                    try container.encode(toolUse.name, forKey: .name)
                    try container.encode(toolUse.input, forKey: .input)
                case .toolResult(let toolResult):
                    try container.encode("tool_result", forKey: .type)
                    try container.encode(toolResult.toolUseId, forKey: .toolUseId)
                    try container.encode(toolResult.content, forKey: .content)
                }
            }
            
            struct ToolUse: Codable {
                let id: String
                let name: String
                let input: [String: AnyCodable]
            }
            
            struct ToolResult: Codable {
                let toolUseId: String
                let content: String
            }
        }
    }
    
    struct Tool: Codable {
        let name: String
        let description: String
        let inputSchema: [String: AnyCodable]
        
        enum CodingKeys: String, CodingKey {
            case name, description
            case inputSchema = "input_schema"
        }
    }
}

struct AnthropicStreamEvent: Codable {
    let type: String
    let index: Int?
    let delta: Delta?
    let contentBlock: ContentBlock?
    
    enum CodingKeys: String, CodingKey {
        case type, index, delta
        case contentBlock = "content_block"
    }
    
    struct Delta: Codable {
        let type: String?
        let text: String?
        let partialJSON: String?
        
        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJSON = "partial_json"
        }
    }
    
    struct ContentBlock: Codable {
        let type: String?
        let toolUse: ToolUse?
        
        enum CodingKeys: String, CodingKey {
            case type
            case toolUse = "tool_use"
        }
        
        struct ToolUse: Codable {
            let id: String
            let name: String
        }
    }
}

