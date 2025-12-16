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
                // Try to decode as Anthropic stream event
                let eventDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let eventType = eventDict?["type"] as? String else { continue }
                
                switch eventType {
                case "content_block_delta":
                    // Handle text content delta
                    if let delta = eventDict?["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        fullText += text
                        onChunk(text)
                    }
                    
                    // Handle tool use delta (arguments being streamed)
                    if let delta = eventDict?["delta"] as? [String: Any],
                       let toolUse = delta["tool_use"] as? [String: Any] {
                        let toolId = toolUse["id"] as? String ?? ""
                        let inputChunk = toolUse["input"] as? String ?? ""
                        
                        // Find or create tool call
                        if let index = toolCalls.firstIndex(where: { $0.id == toolId }) {
                            // Accumulate arguments
                            var currentArgs = toolCalls[index].arguments
                            if let argData = inputChunk.data(using: .utf8),
                               let partialArgs = try? JSONDecoder().decode([String: AnyCodable].self, from: argData) {
                                // Merge partial args
                                for (key, value) in partialArgs {
                                    currentArgs[key] = value
                                }
                                toolCalls[index] = ToolCall(
                                    id: toolCalls[index].id,
                                    name: toolCalls[index].name,
                                    arguments: currentArgs
                                )
                            }
                        }
                    }
                    
                case "content_block_start":
                    // Tool use block started
                    if let contentBlock = eventDict?["content_block"] as? [String: Any],
                       let toolUse = contentBlock["tool_use"] as? [String: Any],
                       let toolId = toolUse["id"] as? String,
                       let toolName = toolUse["name"] as? String {
                        // Create new tool call
                        toolCalls.append(ToolCall(
                            id: toolId,
                            name: toolName,
                            arguments: [:]
                        ))
                        print("🔧 [MiniMaxProvider] Tool call started: \(toolName) (id: \(toolId))")
                    }
                    
                case "message_stop":
                    // Finalize any pending tool calls
                    let validToolCalls = toolCalls.filter { !$0.id.isEmpty && !$0.name.isEmpty }
                    
                    if !validToolCalls.isEmpty {
                        print("🔧 [MiniMaxProvider] Tool calls completed (Anthropic format):")
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
        
        // Convert messages to Anthropic format
        let anthropicMessages = messages.compactMap { message -> AnthropicRequestWithTools.Message? in
            switch message {
            case .user(let content, _):
                return AnthropicRequestWithTools.Message(role: "user", content: content)
            case .assistant(let content, _, _):
                return AnthropicRequestWithTools.Message(role: "assistant", content: content)
            case .toolResults:
                // Anthropic uses a different format for tool results
                // For now, skip tool results or convert them appropriately
                return nil
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
        return AnthropicRequestWithTools(
            model: modelId,
            messages: anthropicMessages,
            maxTokens: 4096,
            stream: true,
            system: config.systemPrompt.isEmpty ? nil : config.systemPrompt,
            tools: anthropicTools
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
    
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, system, tools
        case maxTokens = "max_tokens"
    }
    
    struct Message: Codable {
        let role: String
        let content: String
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


