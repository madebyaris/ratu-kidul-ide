import Foundation
import SwiftData

@Model
final class Attachment {
    @Attribute(.unique) var id: String
    var createdAt: Date
    var type: AttachmentType
    var isLoading: Bool
    var originalName: String?
    var path: String
    var isEphemeral: Bool
    
    init(id: String = UUID().uuidString, type: AttachmentType, path: String, originalName: String? = nil) {
        self.id = id
        self.createdAt = Date()
        self.type = type
        self.path = path
        self.originalName = originalName
        self.isLoading = false
        self.isEphemeral = false
    }
    
    enum AttachmentType: String, Codable {
        case image
        case pdf
        case text
        case webpage
    }
}

