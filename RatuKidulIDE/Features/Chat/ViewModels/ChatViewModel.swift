import SwiftUI
import SwiftData

/// Represents a conversation turn (user prompt + AI responses)
struct ConversationTurn: Identifiable {
    let id: String
    let userPrompt: String
    let userPromptTokens: Int
    let timestamp: Date
    let responses: [Message]
    
    init(messageSet: MessageSet) {
        self.id = messageSet.id
        self.userPrompt = messageSet.userPrompt ?? ""
        self.userPromptTokens = messageSet.userPromptTokens ?? 0
        self.timestamp = messageSet.createdAt
        self.responses = messageSet.messages.sorted { $0.createdAt < $1.createdAt }
    }
}

@MainActor
@Observable
final class ChatViewModel {
    // MARK: - Public Properties
    
    /// Input text - no longer triggers context recalculation on every keystroke
    var inputText: String = ""
    var attachments: [Attachment] = []
    var selectedModels: [ModelConfig] = []
    var messageSets: [MessageSet] = []
    var isLoading: Bool = false
    
    // Pagination state
    var isLoadingMore: Bool = false
    var hasMoreMessages: Bool = true
    private let pageSize: Int = 3
    private var totalMessageCount: Int = 0
    
    // Context management - now uses cached values
    var contextUsage: ContextUsage? {
        // Return cached usage with updated input estimate
        guard let cached = cachedContextUsage else { return nil }
        
        // Quick estimate for current input without async call
        let inputTokenEstimate = inputText.count / 4
        let updatedTotal = cached.breakdown.systemPrompt +
                          cached.breakdown.contextSummary +
                          cached.breakdown.previousMessages +
                          inputTokenEstimate +
                          cached.breakdown.attachments
        
        return ContextUsage(
            totalTokens: updatedTotal,
            contextLimit: cached.contextLimit,
            breakdown: TokenBreakdown(
                systemPrompt: cached.breakdown.systemPrompt,
                contextSummary: cached.breakdown.contextSummary,
                previousMessages: cached.breakdown.previousMessages,
                currentInput: inputTokenEstimate,
                attachments: cached.breakdown.attachments
            )
        )
    }
    var summaryState: SummaryState = .idle
    
    // Computed property for UI - conversation turns
    var conversationTurns: [ConversationTurn] {
        messageSets.map { ConversationTurn(messageSet: $0) }
    }
    
    // MARK: - Private Properties
    private let chatId: String
    private let modelContext: ModelContext
    private let providerRegistry = ProviderRegistry.shared
    private let contextBuilder = ContextBuilder.shared
    private let summaryService = SummaryService.shared
    private let tokenCounter = TokenCounter.shared
    private let keychain = KeychainService.shared
    
    private var chat: Chat?
    
    /// Cached context usage - only recalculated on send or load
    private var cachedContextUsage: ContextUsage?
    
    /// All message sets for context building (may be more than displayed)
    private var allMessageSetsForContext: [MessageSet] = []
    
    // MARK: - Initialization
    init(chatId: String, modelContext: ModelContext) {
        self.chatId = chatId
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Load chat with pagination - only loads last N messages initially
    func loadChat() async {
        // Load the chat object
        let chatDescriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.id == chatId }
        )
        chat = try? modelContext.fetch(chatDescriptor).first
        
        // First, get total count of message sets
        let countDescriptor = FetchDescriptor<MessageSet>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        totalMessageCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0
        
        // Load only the last N message sets for display
        var descriptor = FetchDescriptor<MessageSet>(
            predicate: #Predicate { $0.chatId == chatId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        
        do {
            let recentMessages = try modelContext.fetch(descriptor)
            // Reverse to get chronological order
            messageSets = recentMessages.reversed()
            hasMoreMessages = totalMessageCount > messageSets.count
            
            // Load all messages for context building (but not for display)
            await loadAllMessagesForContext()
            
            // Calculate context usage once
            await recalculateContextUsage()
        } catch {
            print("Error loading chat: \(error)")
        }
    }
    
    /// Load more older messages when user scrolls up
    func loadMoreMessages() async {
        guard hasMoreMessages, !isLoadingMore else { return }
        
        isLoadingMore = true
        
        // Get the oldest currently loaded message's date
        guard let oldestDate = messageSets.first?.createdAt else {
            isLoadingMore = false
            return
        }
        
        // Fetch older messages
        var descriptor = FetchDescriptor<MessageSet>(
            predicate: #Predicate { $0.chatId == chatId && $0.createdAt < oldestDate },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        
        do {
            let olderMessages = try modelContext.fetch(descriptor)
            // Prepend older messages (reversed to get chronological order)
            messageSets = olderMessages.reversed() + messageSets
            hasMoreMessages = messageSets.count < totalMessageCount
        } catch {
            print("Error loading more messages: \(error)")
        }
        
        isLoadingMore = false
    }
    
    func sendMessage() async {
        guard !inputText.isEmpty else { return }
        if selectedModels.isEmpty {
            await loadDefaultModel()
            guard !selectedModels.isEmpty else { return }
        }
        
        isLoading = true
        let userMessage = inputText
        inputText = ""
        
        // Recalculate context before sending
        await recalculateContextUsage()
        
        // 1. Check if we need to summarize first
        await checkAndSummarizeIfNeeded()
        
        // 2. Calculate token count for user message
        let userTokens = await tokenCounter.estimateTokens(userMessage)
        
        // 3. Create message set with user prompt
        let messageSet = MessageSet(chatId: chatId, type: "chat", userPrompt: userMessage)
        messageSet.userPromptTokens = userTokens
        modelContext.insert(messageSet)
        
        // 4. Create user message record
        let userMessageRecord = Message(
            modelConfigId: "user",
            role: .user,
            chat: chat
        )
        userMessageRecord.text = userMessage
        userMessageRecord.state = .complete
        userMessageRecord.tokenCount = userTokens
        userMessageRecord.messageSet = messageSet
        modelContext.insert(userMessageRecord)
        
        // 5. Create AI response messages for each selected model
        for modelConfig in selectedModels {
            let message = Message(
                modelConfigId: modelConfig.id,
                role: .assistant,
                chat: chat
            )
            message.messageSet = messageSet
            messageSet.messages.append(message)
            modelContext.insert(message)
            
            // 6. Build context and stream response
            await streamResponse(for: message, modelConfig: modelConfig, userMessage: userMessage)
        }
        
        // 7. Update chat timestamp
        chat?.updatedAt = Date()
        chat?.isNewChat = false
        
        try? modelContext.save()
        isLoading = false
        
        // Update counts and reload
        totalMessageCount += 1
        messageSets.append(messageSet)
        allMessageSetsForContext.append(messageSet)
        
        // Note: Context is recalculated in onComplete callback after AI response finishes
    }
    
    /// Force recalculate context usage (called on send, load, model change)
    func recalculateContextUsage() async {
        var modelConfig = selectedModels.first
        if modelConfig == nil {
            modelConfig = await getDefaultModel()
        }
        guard let config = modelConfig else { return }
        guard let chatObj = chat else { return }
        
        // Use all messages for context calculation, not just displayed ones
        cachedContextUsage = await contextBuilder.estimateContextUsage(
            chat: chatObj,
            messageSets: allMessageSetsForContext,
            currentInput: inputText,
            attachments: attachments,
            modelConfig: config
        )
    }
    
    // MARK: - Private Methods
    
    /// Load all message sets for context building (separate from pagination display)
    private func loadAllMessagesForContext() async {
        let descriptor = FetchDescriptor<MessageSet>(
            predicate: #Predicate { $0.chatId == chatId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        do {
            allMessageSetsForContext = try modelContext.fetch(descriptor)
        } catch {
            print("Error loading all messages for context: \(error)")
            allMessageSetsForContext = messageSets
        }
    }
    
    private func checkAndSummarizeIfNeeded() async {
        guard let usage = cachedContextUsage,
              let modelConfig = selectedModels.first,
              let chat = chat else { return }
        
        // Check if we should summarize
        let shouldSummarize = await summaryService.shouldSummarize(usage: usage)
        guard shouldSummarize else { return }
        
        summaryState = .summarizing
        
        do {
            // Create summary
            let result = try await summaryService.createSummary(
                messageSets: allMessageSetsForContext,
                previousSummary: chat.contextSummary,
                modelConfig: modelConfig,
                keychain: keychain
            )
            
            // Get messages to exclude
            let excludeIds = await summaryService.getMessagesToExclude(messageSets: allMessageSetsForContext)
            
            // Apply summary to chat
            chat.applySummary(result, excludeMessageIds: excludeIds)
            
            // Calculate tokens saved
            let oldTokens = usage.totalTokens
            await recalculateContextUsage()
            let newTokens = cachedContextUsage?.totalTokens ?? oldTokens
            let saved = max(0, oldTokens - newTokens)
            
            summaryState = .completed(tokensSaved: saved)
            
            try? modelContext.save()
            
            // Reset state after delay
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            summaryState = .idle
            
        } catch {
            summaryState = .error(error.localizedDescription)
        }
    }
    
    private func streamResponse(for message: Message, modelConfig: ModelConfig, userMessage: String) async {
        guard let chat = chat else { return }
        
        // Build optimized context using all messages
        let builtContext = await contextBuilder.buildContext(
            chat: chat,
            messageSets: allMessageSetsForContext,
            currentInput: userMessage,
            attachments: attachments,
            modelConfig: modelConfig
        )
        
        do {
            try await providerRegistry.streamResponse(
                config: modelConfig,
                messages: builtContext.messages,
                tools: nil,
                onChunk: { chunk in
                    Task { @MainActor in
                        message.text += chunk
                        message.state = .streaming
                        try? self.modelContext.save()
                    }
                },
                onToolCall: { toolCall in
                    // Handle tool calls
                },
                onComplete: { fullText, toolCalls in
                    Task { @MainActor in
                        message.text = fullText
                        message.state = .complete
                        // Cache token count for this response
                        message.tokenCount = await self.tokenCounter.estimateTokens(fullText)
                        if let toolCalls = toolCalls {
                            message.toolCalls = try? JSONEncoder().encode(toolCalls)
                        }
                        try? self.modelContext.save()
                        
                        // Recalculate context after AI response completes
                        await self.recalculateContextUsage()
                    }
                },
                onError: { error in
                    Task { @MainActor in
                        message.state = .error
                        message.errorMessage = error.localizedDescription
                        try? self.modelContext.save()
                    }
                }
            )
        } catch {
            message.state = .error
            message.errorMessage = error.localizedDescription
            try? modelContext.save()
        }
    }
    
    private func loadDefaultModel() async {
        if let model = await getDefaultModel() {
            selectedModels = [model]
        }
    }
    
    private func getDefaultModel() async -> ModelConfig? {
        let descriptor = FetchDescriptor<ModelConfig>(
            predicate: #Predicate { $0.isDefault == true },
            sortBy: [SortDescriptor(\.displayName)]
        )
        
        do {
            let models = try modelContext.fetch(descriptor)
            return models.first
        } catch {
            print("Error loading default model: \(error)")
            return nil
        }
    }
}
