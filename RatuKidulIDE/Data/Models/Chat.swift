import Foundation
import SwiftData

@Model
final class Chat {
    @Attribute(.unique) var id: String
    var title: String?
    var createdAt: Date
    var updatedAt: Date?
    var isPinned: Bool
    var isQuickChat: Bool
    var isNewChat: Bool
    var summary: String?
    
    // Context management fields
    var contextSummary: String?       // NEW: Current context summary (auto-generated)
    var totalTokensUsed: Int          // NEW: Running token count for context
    var summaryCreatedAt: Date?       // NEW: When the last summary was created
    var lastSummarizedMessageId: String?  // NEW: Track which messages are summarized
    
    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message]
    
    @Relationship(inverse: \Project.chats)
    var project: Project?
    
    @Relationship
    var parentChat: Chat?
    
    init(id: String = UUID().uuidString) {
        self.id = id
        self.createdAt = Date()
        self.isPinned = false
        self.isQuickChat = false
        self.isNewChat = true
        self.messages = []
        self.totalTokensUsed = 0
    }
}

