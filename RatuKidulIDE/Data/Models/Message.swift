import Foundation
import SwiftData

/// Role of a message in the conversation
enum MessageRole: String, Codable {
    case user       // User's input/prompt
    case assistant  // AI's response
    case system     // System instructions
    case summary    // Context summary (auto-generated)
}

@Model
final class Message {
    @Attribute(.unique) var id: String
    var text: String
    var modelConfigId: String
    var createdAt: Date
    var state: MessageState
    var role: MessageRole        // NEW: Track message role
    var tokenCount: Int?         // NEW: Cached token count for this message
    var errorMessage: String?
    var isReview: Bool
    var toolCalls: Data?      // JSON encoded
    var toolResults: Data?    // JSON encoded
    var includedInContext: Bool  // NEW: Whether this message is included in current context
    
    @Relationship
    var chat: Chat?
    
    @Relationship
    var messageSet: MessageSet?
    
    @Relationship(deleteRule: .nullify)
    var attachments: [Attachment]
    
    init(
        id: String = UUID().uuidString,
        text: String = "",
        modelConfigId: String,
        role: MessageRole = .assistant,
        chat: Chat? = nil
    ) {
        self.id = id
        self.text = text
        self.modelConfigId = modelConfigId
        self.role = role
        self.createdAt = Date()
        self.state = role == .user ? .complete : .streaming
        self.isReview = false
        self.attachments = []
        self.chat = chat
        self.includedInContext = true
    }
    
    enum MessageState: String, Codable {
        case streaming
        case complete
        case error
        case cancelled
    }
}

@Model
final class MessageSet {
    @Attribute(.unique) var id: String
    var chatId: String
    var createdAt: Date
    var type: String
    var userPrompt: String?      // NEW: The original user prompt for this turn
    var userPromptTokens: Int?   // NEW: Token count for user prompt
    
    @Relationship(deleteRule: .cascade)
    var messages: [Message]
    
    init(id: String = UUID().uuidString, chatId: String, type: String = "chat", userPrompt: String? = nil) {
        self.id = id
        self.chatId = chatId
        self.createdAt = Date()
        self.type = type
        self.userPrompt = userPrompt
        self.messages = []
    }
}

