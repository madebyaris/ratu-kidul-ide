import Foundation

enum ProviderError: Error {
    case missingAPIKey
    case requestFailed
    case unknownProvider
    case invalidResponse
}

/// Protocol for all AI model providers
protocol AIProvider: Actor {
    /// Provider identifier (e.g., "openai", "anthropic")
    var id: String { get }
    
    /// Human-readable name
    var displayName: String { get }
    
    /// Stream a response from the model
    func streamResponse(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (String, [ToolCall]?) async -> Void,
        onError: @escaping (Error) -> Void
    ) async throws
    
    /// Validate API key
    func validateAPIKey(_ key: String) async throws -> Bool
    
    /// List available models
    func listModels() async throws -> [Model]
}

/// Common message format for all providers
enum LLMMessage {
    case user(content: String, attachments: [Attachment])
    case assistant(content: String, model: String?, toolCalls: [ToolCall])
    case toolResults([ToolResult])
}

struct ToolCall: Codable, Identifiable {
    let id: String
    let name: String
    let arguments: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case arguments
    }
    
    init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments.mapValues { AnyCodable($0) }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let argsDict = try container.decode([String: AnyCodable].self, forKey: .arguments)
        arguments = argsDict
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
    }
}

struct ToolResult: Codable {
    let id: String
    let content: String
}

struct UserTool: Codable, Identifiable {
    let id: String
    let toolsetName: String
    let displayName: String
    let description: String?
    let inputSchema: [String: AnyCodable]
    
    var namespacedName: String {
        "\(toolsetName)_\(displayName)"
    }
}

struct Model: Codable, Identifiable {
    let id: String
    let displayName: String
    let isEnabled: Bool
    let supportedAttachmentTypes: [Attachment.AttachmentType]
}

// Helper for encoding/decoding Any values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}

