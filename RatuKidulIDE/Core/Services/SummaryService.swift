import Foundation
import SwiftData

/// Service for managing conversation summaries when context window is near capacity
actor SummaryService {
    static let shared = SummaryService()
    
    private let tokenCounter = TokenCounter.shared
    private let summaryThreshold = 0.95 // Trigger summary at 95% capacity
    
    private init() {}
    
    // MARK: - Public API
    
    /// Check if summarization is needed based on context usage
    func shouldSummarize(usage: ContextUsage) -> Bool {
        return usage.percentage >= summaryThreshold
    }
    
    /// Create a summary of the conversation
    func createSummary(
        messageSets: [MessageSet],
        previousSummary: String?,
        modelConfig: ModelConfig,
        keychain: KeychainService
    ) async throws -> SummaryResult {
        // Build the conversation text to summarize
        var conversationText = ""
        var messageCount = 0
        
        for messageSet in messageSets {
            if let userPrompt = messageSet.userPrompt {
                conversationText += "User: \(userPrompt)\n\n"
                messageCount += 1
            }
            
            for message in messageSet.messages where message.state == .complete {
                conversationText += "Assistant: \(message.text)\n\n"
                messageCount += 1
            }
        }
        
        // Build the summary prompt
        let summaryPrompt = buildSummaryPrompt(
            conversation: conversationText,
            previousSummary: previousSummary
        )
        
        // Call the AI to generate summary
        let summary = try await generateSummary(
            prompt: summaryPrompt,
            modelConfig: modelConfig,
            keychain: keychain
        )
        
        let summaryTokens = await tokenCounter.estimateTokens(summary)
        
        return SummaryResult(
            summary: summary,
            tokenCount: summaryTokens,
            messagesIncluded: messageCount,
            createdAt: Date()
        )
    }
    
    /// Determine which messages can be excluded after summarization
    func getMessagesToExclude(
        messageSets: [MessageSet],
        keepRecentCount: Int = 4 // Keep last 4 message sets
    ) -> [String] {
        guard messageSets.count > keepRecentCount else {
            return []
        }
        
        var excludeIds: [String] = []
        let setsToExclude = messageSets.dropLast(keepRecentCount)
        
        for messageSet in setsToExclude {
            for message in messageSet.messages {
                excludeIds.append(message.id)
            }
        }
        
        return excludeIds
    }
    
    // MARK: - Private Helpers
    
    private func buildSummaryPrompt(conversation: String, previousSummary: String?) -> String {
        var prompt = """
        Please create a concise summary of the following conversation. The summary should:
        1. Preserve key decisions and conclusions made
        2. Maintain important context about the project or task
        3. Note any pending tasks, questions, or action items
        4. Be written in a way that provides context for continuing the conversation
        
        Keep the summary under 500 words while retaining all critical information.
        
        """
        
        if let previous = previousSummary {
            prompt += """
            
            Previous conversation summary:
            \(previous)
            
            """
        }
        
        prompt += """
        
        Recent conversation to summarize:
        \(conversation)
        
        Summary:
        """
        
        return prompt
    }
    
    private func generateSummary(
        prompt: String,
        modelConfig: ModelConfig,
        keychain: KeychainService
    ) async throws -> String {
        // Use the provider registry to get the appropriate provider
        let provider = await ProviderRegistry.shared.getProvider(for: modelConfig.modelId)
        
        var result = ""
        
        // Create a temporary config for summary generation (non-streaming for simplicity)
        try await provider.streamResponse(
            config: modelConfig,
            messages: [.user(content: prompt, attachments: [])],
            tools: nil,
            onChunk: { chunk in
                result += chunk
            },
            onToolCall: { _ in },
            onComplete: { fullText, _ in
                result = fullText
            },
            onError: { error in
                print("Summary generation error: \(error)")
            }
        )
        
        return result
    }
}

/// Result of creating a conversation summary
struct SummaryResult {
    let summary: String
    let tokenCount: Int
    let messagesIncluded: Int
    let createdAt: Date
}

// MARK: - Chat Extension for Summary Management

extension Chat {
    /// Apply a summary result to this chat
    @MainActor
    func applySummary(_ result: SummaryResult, excludeMessageIds: [String]) {
        self.contextSummary = result.summary
        self.summaryCreatedAt = result.createdAt
        
        // Mark old messages as excluded from context
        for message in self.messages {
            if excludeMessageIds.contains(message.id) {
                message.includedInContext = false
            }
        }
        
        // Update the last summarized message ID
        if let lastExcluded = excludeMessageIds.last {
            self.lastSummarizedMessageId = lastExcluded
        }
    }
    
    /// Get messages that should be included in context (not summarized)
    var activeMessages: [Message] {
        messages.filter { $0.includedInContext }
    }
    
    /// Check if this chat has a context summary
    var hasSummary: Bool {
        contextSummary != nil && !contextSummary!.isEmpty
    }
}

// MARK: - Summary State for UI

enum SummaryState: Equatable {
    case idle
    case checking
    case summarizing
    case completed(tokensSaved: Int)
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .checking, .summarizing:
            return true
        default:
            return false
        }
    }
    
    var statusMessage: String {
        switch self {
        case .idle:
            return ""
        case .checking:
            return "Checking context..."
        case .summarizing:
            return "Creating summary..."
        case .completed(let saved):
            return "Summarized, saved \(saved) tokens"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

