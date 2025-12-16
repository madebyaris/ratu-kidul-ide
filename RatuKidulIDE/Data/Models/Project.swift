import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    var path: String?  // Stores the folder URL path for file operations
    var createdAt: Date
    var updatedAt: Date
    var isCollapsed: Bool
    var contextText: String?
    var magicProjectsEnabled: Bool
    
    @Relationship(deleteRule: .cascade)
    var chats: [Chat]
    
    @Relationship
    var attachments: [Attachment]
    
    init(id: String = UUID().uuidString, name: String, path: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isCollapsed = false
        self.magicProjectsEnabled = true
        self.chats = []
        self.attachments = []
    }
}

