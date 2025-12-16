import Foundation

/// Represents the current context window usage
struct ContextUsage {
    let totalTokens: Int
    let contextLimit: Int
    let breakdown: TokenBreakdown
    
    var percentage: Double {
        guard contextLimit > 0 else { return 0 }
        return Double(totalTokens) / Double(contextLimit)
    }
    
    var isNearLimit: Bool { percentage >= 0.95 }
    var isWarning: Bool { percentage >= 0.80 }
    
    var remainingTokens: Int {
        max(0, contextLimit - totalTokens)
    }
}

/// Breakdown of token usage by category
struct TokenBreakdown {
    let systemPrompt: Int
    let contextSummary: Int
    let previousMessages: Int
    let currentInput: Int
    let attachments: Int
    
    var total: Int {
        systemPrompt + contextSummary + previousMessages + currentInput + attachments
    }
}

/// Service for estimating and tracking token usage
actor TokenCounter {
    static let shared = TokenCounter()
    
    // Average characters per token (GPT-style tokenization approximation)
    // This is a rough estimate - actual tokenization varies by model
    private let charsPerToken: Double = 4.0
    
    // Cache for computed token counts
    private var tokenCache: [String: Int] = [:]
    
    private init() {}
    
    // MARK: - Public API
    
    /// Estimate tokens for a given text
    func estimateTokens(_ text: String) -> Int {
        // Check cache first
        let cacheKey = String(text.hashValue)
        if let cached = tokenCache[cacheKey] {
            return cached
        }
        
        // Calculate estimate
        let estimate = calculateTokenEstimate(text)
        
        // Cache result (limit cache size)
        if tokenCache.count < 1000 {
            tokenCache[cacheKey] = estimate
        }
        
        return estimate
    }
    
    /// Calculate total context usage for a chat
    func calculateContextUsage(
        systemPrompt: String,
        contextSummary: String?,
        messages: [Message],
        currentInput: String,
        attachments: [Attachment],
        contextLimit: Int
    ) -> ContextUsage {
        let systemTokens = estimateTokens(systemPrompt)
        let summaryTokens = contextSummary.map { estimateTokens($0) } ?? 0
        let messageTokens = messages.reduce(0) { total, message in
            // Use cached token count if available
            if let cached = message.tokenCount {
                return total + cached
            }
            return total + estimateTokens(message.text)
        }
        let inputTokens = estimateTokens(currentInput)
        let attachmentTokens = calculateAttachmentTokens(attachments)
        
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
    
    /// Estimate tokens for a file based on its size
    func estimateFileTokens(content: String) -> Int {
        return estimateTokens(content)
    }
    
    /// Determine if a file is "large" (would use significant context)
    func isLargeFile(tokenCount: Int, contextLimit: Int) -> Bool {
        // File is considered large if it would use more than 10% of context
        return Double(tokenCount) / Double(contextLimit) > 0.10
    }
    
    /// Get recommended handling for a file based on its size
    func getFileHandlingStrategy(tokenCount: Int) -> FileHandlingStrategy {
        switch tokenCount {
        case 0..<2000:
            return .includeFullly
        case 2000..<10000:
            return .includeWithTruncation
        default:
            return .summarizeFirst
        }
    }
    
    /// Clear the token cache
    func clearCache() {
        tokenCache.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func calculateTokenEstimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        
        // Base estimate from character count
        var estimate = Int(ceil(Double(text.count) / charsPerToken))
        
        // Adjust for code blocks (tend to have more tokens per character)
        let codeBlockCount = text.components(separatedBy: "```").count - 1
        if codeBlockCount > 0 {
            estimate = Int(Double(estimate) * 1.1)
        }
        
        // Adjust for whitespace-heavy content
        let whitespaceRatio = Double(text.filter { $0.isWhitespace }.count) / Double(text.count)
        if whitespaceRatio > 0.3 {
            estimate = Int(Double(estimate) * 0.9)
        }
        
        // Minimum of 1 token for non-empty text
        return max(1, estimate)
    }
    
    private func calculateAttachmentTokens(_ attachments: [Attachment]) -> Int {
        // For now, estimate based on attachment type
        // In a real implementation, we'd read file contents
        var total = 0
        for attachment in attachments {
            switch attachment.type {
            case .text:
                // Estimate based on typical text file
                total += 500
            case .image:
                // Images are typically converted to tokens differently
                total += 1000
            case .pdf:
                total += 2000
            case .webpage:
                total += 1000
            }
        }
        return total
    }
}

/// Strategy for handling files in context
enum FileHandlingStrategy {
    case includeFullly       // File is small enough to include completely
    case includeWithTruncation  // Include with truncation notice
    case summarizeFirst      // File is too large, summarize before including
    
    var description: String {
        switch self {
        case .includeFullly:
            return "Include full content"
        case .includeWithTruncation:
            return "Include with truncation"
        case .summarizeFirst:
            return "Summarize before including"
        }
    }
}

// MARK: - Convenience Extensions

extension ContextUsage {
    /// Format the usage as a display string (e.g., "1.2K / 128K")
    var displayString: String {
        let usedStr = formatTokenCount(totalTokens)
        let limitStr = formatTokenCount(contextLimit)
        return "\(usedStr) / \(limitStr)"
    }
    
    /// Format with percentage (e.g., "1.2K / 128K (0.9%)")
    var displayStringWithPercentage: String {
        let percentStr = String(format: "%.1f%%", percentage * 100)
        return "\(displayString) (\(percentStr))"
    }
    
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(count / 1_000_000)M"
        } else if count >= 1_000 {
            let k = Double(count) / 1000.0
            if k >= 100 {
                return "\(Int(k))K"
            }
            return String(format: "%.1fK", k)
        }
        return "\(count)"
    }
}

