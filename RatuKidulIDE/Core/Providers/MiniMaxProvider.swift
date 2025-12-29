import Foundation

/// MiniMax AI Provider
/// Uses Anthropic-compatible API endpoint as recommended by MiniMax
/// Base URL: https://api.minimax.io/anthropic
actor MiniMaxProvider: AIProvider {
    let id = "minimax"
    let displayName = "MiniMax"
    
    private let baseURL = URL(string: "https://api.minimax.io/anthropic")!
    private let keychain: KeychainService
    
    init(keychain: KeychainService) {
        self.keychain = keychain
    }
    
    /// Get the API URL for requests
    private func getAPIURL() -> URL {
        return baseURL.appendingPathComponent("v1/messages")
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
        
        // Use Anthropic-compatible endpoint
        let endpointURL = getAPIURL()
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body = try buildRequestBody(config: config, messages: messages, tools: tools)
        let requestBodyData = try JSONEncoder().encode(body)
        request.httpBody = requestBodyData
        
        // Debug: Log the full request body
        if let requestJSON = String(data: requestBodyData, encoding: .utf8) {
            print("📤 [MiniMaxProvider] Request body (Anthropic-compatible):\n\(requestJSON)")
        }
        
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
            print("❌ [MiniMaxProvider] API Error (\(httpResponse.statusCode)): \(errorMessage)")
            onError(ProviderError.requestFailed)
            throw ProviderError.requestFailed
        }
        
        var fullText = ""
        var toolCalls: [ToolCall] = []
        var toolCallPartialJSON: [String: String] = [:] // Track partial JSON per tool ID
        var indexToToolCall: [Int: Int] = [:] // Map content block index to toolCalls array index
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            
            // Skip empty lines and [DONE] marker
            if jsonStr.isEmpty || jsonStr == "[DONE]" {
                continue
            }
            
            guard let data = jsonStr.data(using: .utf8) else { continue }
            
            // Debug: Log raw response chunks (first few only)
            if toolCalls.isEmpty && fullText.count < 100 {
                if let responseJSON = String(data: data, encoding: .utf8) {
                    print("📥 [MiniMaxProvider] Response chunk:\n\(responseJSON)")
                }
            }
            
            do {
                // Decode as Anthropic stream event
                let decoder = JSONDecoder()
                let event = try decoder.decode(AnthropicStreamEvent.self, from: data)
                
                switch event.type {
                case "content_block_start":
                    // Tool use block started
                    if let contentBlock = event.contentBlock,
                       contentBlock.type == "tool_use",
                       let toolId = contentBlock.toolUse?.id,
                       let toolName = contentBlock.toolUse?.name,
                       let index = event.index {
                        // Create new tool call
                        let toolCallIndex = toolCalls.count
                        let newToolCall = ToolCall(
                            id: toolId,
                            name: toolName,
                            arguments: [:]
                        )
                        toolCalls.append(newToolCall)
                        toolCallPartialJSON[toolId] = "" // Initialize partial JSON accumulator
                        indexToToolCall[index] = toolCallIndex // Map content block index to tool call index
                        print("🔧 [MiniMaxProvider] Tool call started: \(toolName) (id: \(toolId), content_block_index: \(index), tool_call_index: \(toolCallIndex))")
                        onToolCall(newToolCall) // Notify immediately
                    } else {
                        // Debug: log what we got
                        if let contentBlock = event.contentBlock {
                            print("🔍 [MiniMaxProvider] content_block_start - type: \(contentBlock.type ?? "nil"), index: \(event.index ?? -1)")
                        }
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
                           let partialJSON = delta.partialJSON,
                           let contentBlockIndex = event.index {
                            // Map content block index to tool call index
                            if let toolCallIndex = indexToToolCall[contentBlockIndex],
                               toolCallIndex < toolCalls.count {
                                let toolId = toolCalls[toolCallIndex].id
                                // Accumulate partial JSON
                                toolCallPartialJSON[toolId, default: ""] += partialJSON
                                print("📝 [MiniMaxProvider] Accumulating JSON for tool \(toolCalls[toolCallIndex].name) (content_block_index: \(contentBlockIndex), tool_call_index: \(toolCallIndex), chunk length: \(partialJSON.count))")
                            } else {
                                print("⚠️ [MiniMaxProvider] No tool call mapped for content_block_index \(contentBlockIndex) (have \(toolCalls.count) tool calls)")
                            }
                        }
                    }
                    
                case "content_block_stop":
                    // Finalize tool call arguments when block stops
                    if let contentBlockIndex = event.index {
                        // Map content block index to tool call index
                        if let toolCallIndex = indexToToolCall[contentBlockIndex],
                           toolCallIndex < toolCalls.count {
                            let toolId = toolCalls[toolCallIndex].id
                            if let accumulatedJSON = toolCallPartialJSON[toolId],
                               !accumulatedJSON.isEmpty {
                                print("🔍 [MiniMaxProvider] Finalizing tool call \(toolCalls[toolCallIndex].name) (content_block_index: \(contentBlockIndex), tool_call_index: \(toolCallIndex), JSON length: \(accumulatedJSON.count))")
                                // Try to parse the complete JSON
                                if let jsonData = accumulatedJSON.data(using: .utf8),
                                   let args = try? decoder.decode([String: AnyCodable].self, from: jsonData) {
                                    toolCalls[toolCallIndex] = ToolCall(
                                        id: toolCalls[toolCallIndex].id,
                                        name: toolCalls[toolCallIndex].name,
                                        arguments: args
                                    )
                                    print("✅ [MiniMaxProvider] Parsed arguments for \(toolCalls[toolCallIndex].name): \(args.count) params")
                                    for (key, value) in args {
                                        print("   - \(key): \(String(describing: value.value).prefix(50))")
                                    }
                                } else {
                                    print("⚠️ [MiniMaxProvider] Failed to parse JSON for \(toolCalls[toolCallIndex].name)")
                                    print("   JSON preview: \(String(accumulatedJSON.prefix(200)))")
                                }
                                toolCallPartialJSON.removeValue(forKey: toolId)
                            } else {
                                print("⚠️ [MiniMaxProvider] content_block_stop for content_block_index \(contentBlockIndex) but no accumulated JSON")
                            }
                        } else {
                            print("⚠️ [MiniMaxProvider] content_block_stop content_block_index \(contentBlockIndex) not mapped to any tool call (have \(toolCalls.count) tool calls)")
                        }
                    }
                    
                case "message_stop":
                    // Finalize any pending tool calls
                    let validToolCalls = toolCalls.filter { !$0.id.isEmpty && !$0.name.isEmpty }
                    
                    if !validToolCalls.isEmpty {
                        print("🔧 [MiniMaxProvider] Tool calls completed:")
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
                print("⚠️ [MiniMaxProvider] Failed to parse event: \(error)")
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
    ) throws -> AnthropicRequestWithTools {
        // Extract model name from full ID (e.g., "minimax/MiniMax-M2" → "MiniMax-M2")
        let modelId = config.modelId.replacingOccurrences(of: "minimax/", with: "")
        
        // Convert messages to Anthropic format with content blocks
        var anthropicMessages: [AnthropicRequestWithTools.Message] = []
        
        for message in messages {
            switch message {
            case .user(let content, _):
                // User messages: content is array of text blocks
                anthropicMessages.append(AnthropicRequestWithTools.Message(
                    role: "user",
                    content: [.text(content)]
                ))
                
            case .assistant(let content, _, let toolCalls):
                // Assistant messages: can have text and/or tool_use blocks
                var contentBlocks: [AnthropicRequestWithTools.Message.ContentBlock] = []
                
                // Add text content if present
                if !content.isEmpty {
                    contentBlocks.append(.text(content))
                }
                
                // Add tool_use blocks if present
                for toolCall in toolCalls {
                    contentBlocks.append(.toolUse(AnthropicRequestWithTools.Message.ContentBlock.ToolUse(
                        id: toolCall.id,
                        name: toolCall.name,
                        input: toolCall.arguments
                    )))
                }
                
                anthropicMessages.append(AnthropicRequestWithTools.Message(
                    role: "assistant",
                    content: contentBlocks
                ))
                
            case .toolResults(let results):
                // Tool results: Anthropic sends these as user messages with tool_result blocks
                var contentBlocks: [AnthropicRequestWithTools.Message.ContentBlock] = []
                for result in results {
                    contentBlocks.append(.toolResult(AnthropicRequestWithTools.Message.ContentBlock.ToolResult(
                        toolUseId: result.id,
                        content: result.content
                    )))
                }
                anthropicMessages.append(AnthropicRequestWithTools.Message(
                    role: "user",
                    content: contentBlocks
                ))
            }
        }
        
        // Convert tools to Anthropic format if present
        let anthropicTools: [AnthropicRequestWithTools.Tool]? = tools?.map { tool in
            AnthropicRequestWithTools.Tool(
                        name: tool.namespacedName,
                        description: tool.description ?? "",
                inputSchema: tool.inputSchema
                )
            }
        
        // Build Anthropic-compatible request
        // Set tool_choice to "any" if tools are provided to encourage tool usage
        let toolChoice: AnthropicRequestWithTools.ToolChoice? = (anthropicTools != nil && !anthropicTools!.isEmpty) ? .any : nil
        
        return AnthropicRequestWithTools(
            model: modelId,
            messages: anthropicMessages,
            maxTokens: 4096,
            stream: true,
            system: config.systemPrompt.isEmpty ? nil : config.systemPrompt,
            tools: anthropicTools,
            toolChoice: toolChoice
        )
    }
}

// MARK: - Anthropic-Compatible API Types (for MiniMax)

/// Extended AnthropicRequest to support tools
struct AnthropicRequestWithTools: Codable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let stream: Bool
    let system: String?
    let tools: [Tool]?
    let toolChoice: ToolChoice?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, system, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }
    
    enum ToolChoice: Codable {
        case auto
        case any
        case tool(name: String)
        
        enum CodingKeys: String, CodingKey {
            case type, name
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .auto:
                try container.encode("auto", forKey: .type)
            case .any:
                try container.encode("any", forKey: .type)
            case .tool(let name):
                try container.encode("tool", forKey: .type)
                try container.encode(name, forKey: .name)
        }
    }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "auto":
                self = .auto
            case "any":
                self = .any
            case "tool":
                let name = try container.decode(String.self, forKey: .name)
                self = .tool(name: name)
            default:
                self = .auto
            }
        }
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

