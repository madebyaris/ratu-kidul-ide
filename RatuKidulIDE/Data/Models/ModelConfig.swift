import Foundation
import SwiftData

@Model
final class ModelConfig: Identifiable {
    @Attribute(.unique) var id: String
    var displayName: String
    var modelId: String
    var author: Author
    var systemPrompt: String
    var isDefault: Bool
    var budgetTokens: Int?
    var reasoningEffort: ReasoningEffort?
    var newUntil: Date?
    var contextWindow: Int?
    
    /// Custom base URL for OpenAI/Anthropic compatible providers
    var customBaseURL: String?
    
    /// Returns the context window, defaulting to 128000 if not set
    var effectiveContextWindow: Int {
        contextWindow ?? 128000
    }
    
    init(id: String, displayName: String, modelId: String, author: Author = .system, systemPrompt: String = "", isDefault: Bool = false, contextWindow: Int = 128000, customBaseURL: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.modelId = modelId
        self.author = author
        self.systemPrompt = systemPrompt
        self.isDefault = isDefault
        self.contextWindow = contextWindow
        self.customBaseURL = customBaseURL
    }
    
    enum Author: String, Codable {
        case user
        case system
    }
    
    enum ReasoningEffort: String, Codable {
        case low
        case medium
        case high
    }
}

