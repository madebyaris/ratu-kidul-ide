import Foundation
import SwiftData

/// Result of building context for an API request
struct BuiltContext {
    let messages: [LLMMessage]
    let tokenUsage: ContextUsage
    let truncatedFiles: [String]      // Files that were truncated
    let summarizedFiles: [String]     // Files that were summarized
    let excludedMessages: [String]    // Message IDs excluded due to space
}

/// Service for building optimized context for AI requests
actor ContextBuilder {
    static let shared = ContextBuilder()
    
    private let tokenCounter = TokenCounter.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Build context for an AI request, optimizing for the context window
    func buildContext(
        chat: Chat,
        messageSets: [MessageSet],
        currentInput: String,
        attachments: [Attachment],
        modelConfig: ModelConfig
    ) async -> BuiltContext {
        let contextLimit = modelConfig.effectiveContextWindow
        let systemPrompt = modelConfig.systemPrompt
        
        var messages: [LLMMessage] = []
        var truncatedFiles: [String] = []
        var summarizedFiles: [String] = []
        var excludedMessageIds: [String] = []
        
        // 1. Start with system prompt (always included)
        var usedTokens = await tokenCounter.estimateTokens(systemPrompt)
        
        // 2. Add context summary if available
        if let summary = chat.contextSummary {
            let summaryTokens = await tokenCounter.estimateTokens(summary)
            usedTokens += summaryTokens
            messages.append(.system(content: "Previous conversation summary:\n\(summary)"))
        }
        
        // 3. Reserve tokens for current input and expected response
        let inputTokens = await tokenCounter.estimateTokens(currentInput)
        let attachmentTokens = await calculateAttachmentTokens(attachments)
        let reservedForResponse = min(4000, contextLimit / 4) // Reserve 25% or 4K for response
        let reservedTokens = inputTokens + attachmentTokens + reservedForResponse
        
        // 4. Calculate available tokens for history
        let availableForHistory = contextLimit - usedTokens - reservedTokens
        
        // 5. Build message history (most recent first, then reverse)
        var historyMessages: [(LLMMessage, Int)] = [] // (message, tokens)
        var historyTokens = 0
        
        // Process message sets from newest to oldest
        for messageSet in messageSets.reversed() {
            // Add user prompt
            if let userPrompt = messageSet.userPrompt {
                var promptTokens: Int
                if let cached = messageSet.userPromptTokens {
                    promptTokens = cached
                } else {
                    promptTokens = await tokenCounter.estimateTokens(userPrompt)
                }
                
                if historyTokens + promptTokens <= availableForHistory {
                    historyMessages.append((.user(content: userPrompt, attachments: []), promptTokens))
                    historyTokens += promptTokens
                } else {
                    // No more room for history
                    break
                }
            }
            
            // Add AI responses
            for message in messageSet.messages.sorted(by: { $0.createdAt < $1.createdAt }) {
                guard message.state == .complete else { continue }
                
                var messageTokens: Int
                if let cached = message.tokenCount {
                    messageTokens = cached
                } else {
                    messageTokens = await tokenCounter.estimateTokens(message.text)
                }
                
                if historyTokens + messageTokens <= availableForHistory {
                    historyMessages.append((
                        .assistant(content: message.text, model: message.modelConfigId, toolCalls: []),
                        messageTokens
                    ))
                    historyTokens += messageTokens
                } else {
                    excludedMessageIds.append(message.id)
                }
            }
        }
        
        // Reverse to get chronological order
        historyMessages.reverse()
        messages.append(contentsOf: historyMessages.map { $0.0 })
        
        // 6. Process attachments for current input
        let processedAttachments = await processAttachments(
            attachments,
            contextLimit: contextLimit,
            truncatedFiles: &truncatedFiles,
            summarizedFiles: &summarizedFiles
        )
        
        // 7. Add current user input with attachments
        messages.append(.user(content: currentInput, attachments: processedAttachments))
        
        // 8. Calculate final token usage
        var contextSummaryTokens = 0
        if let summary = chat.contextSummary {
            contextSummaryTokens = await tokenCounter.estimateTokens(summary)
        }
        
        let breakdown = TokenBreakdown(
            systemPrompt: await tokenCounter.estimateTokens(systemPrompt),
            contextSummary: contextSummaryTokens,
            previousMessages: historyTokens,
            currentInput: inputTokens,
            attachments: attachmentTokens
        )
        
        let usage = ContextUsage(
            totalTokens: breakdown.total,
            contextLimit: contextLimit,
            breakdown: breakdown
        )
        
        return BuiltContext(
            messages: messages,
            tokenUsage: usage,
            truncatedFiles: truncatedFiles,
            summarizedFiles: summarizedFiles,
            excludedMessages: excludedMessageIds
        )
    }
    
    /// Estimate context usage without building full context
    func estimateContextUsage(
        chat: Chat,
        messageSets: [MessageSet],
        currentInput: String,
        attachments: [Attachment],
        modelConfig: ModelConfig
    ) async -> ContextUsage {
        let contextLimit = modelConfig.effectiveContextWindow
        
        // Calculate each component
        let systemTokens = await tokenCounter.estimateTokens(modelConfig.systemPrompt)
        var summaryTokens = 0
        if let summary = chat.contextSummary {
            summaryTokens = await tokenCounter.estimateTokens(summary)
        }
        
        var messageTokens = 0
        for messageSet in messageSets {
            if let prompt = messageSet.userPrompt {
                if let cached = messageSet.userPromptTokens {
                    messageTokens += cached
                } else {
                    messageTokens += await tokenCounter.estimateTokens(prompt)
                }
            }
            for message in messageSet.messages where message.state == .complete {
                if let cached = message.tokenCount {
                    messageTokens += cached
                } else {
                    messageTokens += await tokenCounter.estimateTokens(message.text)
                }
            }
        }
        
        let inputTokens = await tokenCounter.estimateTokens(currentInput)
        let attachmentTokens = await calculateAttachmentTokens(attachments)
        
        let breakdown = TokenBreakdown(
            systemPrompt: systemTokens,
            contextSummary: summaryTokens,
            previousMessages: messageTokens,
            currentInput: inputTokens,
            attachments: attachmentTokens
        )
        
        return ContextUsage(
            totalTokens: breakdown.total,
            contextLimit: contextLimit,
            breakdown: breakdown
        )
    }
    
    // MARK: - Private Helpers
    
    private func calculateAttachmentTokens(_ attachments: [Attachment]) async -> Int {
        var total = 0
        for attachment in attachments {
            // In a real implementation, read file content and estimate
            switch attachment.type {
            case .text:
                total += 500 // Placeholder - would read actual file
            case .image:
                total += 1000
            case .pdf:
                total += 2000
            case .webpage:
                total += 1000
            }
        }
        return total
    }
    
    private func processAttachments(
        _ attachments: [Attachment],
        contextLimit: Int,
        truncatedFiles: inout [String],
        summarizedFiles: inout [String]
    ) async -> [Attachment] {
        // For now, return attachments as-is
        // In a full implementation, we would:
        // 1. Read file contents
        // 2. Check token count
        // 3. Truncate or summarize if needed
        return attachments
    }
}

// MARK: - File Content Processing

extension ContextBuilder {
    /// Process a file's content for inclusion in context
    func processFileContent(
        _ content: String,
        filename: String,
        contextLimit: Int
    ) async -> ProcessedFileContent {
        let tokens = await tokenCounter.estimateTokens(content)
        let strategy = await tokenCounter.getFileHandlingStrategy(tokenCount: tokens)
        
        switch strategy {
        case .includeFullly:
            return ProcessedFileContent(
                content: content,
                tokens: tokens,
                wasModified: false,
                strategy: strategy
            )
            
        case .includeWithTruncation:
            let maxChars = 8000 // Roughly 2K tokens
            let truncated = String(content.prefix(maxChars))
            let notice = "\n\n[... File truncated. Showing first \(maxChars) characters of \(content.count) total ...]"
            return ProcessedFileContent(
                content: truncated + notice,
                tokens: await tokenCounter.estimateTokens(truncated + notice),
                wasModified: true,
                strategy: strategy
            )
            
        case .summarizeFirst:
            // In a real implementation, we'd call the AI to summarize
            // For now, truncate heavily with a note
            let maxChars = 4000
            let truncated = String(content.prefix(maxChars))
            let notice = "\n\n[... Large file (\(content.count) chars). This is a preview. Consider asking for specific sections ...]"
            return ProcessedFileContent(
                content: truncated + notice,
                tokens: await tokenCounter.estimateTokens(truncated + notice),
                wasModified: true,
                strategy: strategy
            )
        }
    }
}

/// Result of processing a file for context inclusion
struct ProcessedFileContent {
    let content: String
    let tokens: Int
    let wasModified: Bool
    let strategy: FileHandlingStrategy
}

// MARK: - LLMMessage Extension

extension LLMMessage {
    static func system(content: String) -> LLMMessage {
        // System messages are treated as user messages with special formatting
        return .user(content: "[System]: \(content)", attachments: [])
    }
}

