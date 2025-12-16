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
    var inputText: String = "" {
        didSet {
            Task { await updateContextUsage() }
        }
    }
    var attachments: [Attachment] = []
    var selectedModels: [ModelConfig] = []
    var messageSets: [MessageSet] = []
    var isLoading: Bool = false
    
    // Context management
    var contextUsage: ContextUsage?
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
    
    // MARK: - Initialization
    init(chatId: String, modelContext: ModelContext) {
        self.chatId = chatId
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    func loadChat() async {
        // Load the chat object
        let chatDescriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.id == chatId }
        )
        chat = try? modelContext.fetch(chatDescriptor).first
        
        // Load message sets
        let descriptor = FetchDescriptor<MessageSet>(
            predicate: #Predicate { $0.chatId == chatId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        do {
            messageSets = try modelContext.fetch(descriptor)
            await updateContextUsage()
        } catch {
            print("Error loading chat: \(error)")
        }
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
        await loadChat()
    }
    
    /// Update context usage estimate based on current state
    func updateContextUsage() async {
        var modelConfig = selectedModels.first
        if modelConfig == nil {
            modelConfig = await getDefaultModel()
        }
        guard let config = modelConfig else { return }
        guard let chatObj = chat else { return }
        
        contextUsage = await contextBuilder.estimateContextUsage(
            chat: chatObj,
            messageSets: messageSets,
            currentInput: inputText,
            attachments: attachments,
            modelConfig: config
        )
    }
    
    // MARK: - Private Methods
    
    private func checkAndSummarizeIfNeeded() async {
        guard let usage = contextUsage,
              let modelConfig = selectedModels.first,
              let chat = chat else { return }
        
        // Check if we should summarize
        let shouldSummarize = await summaryService.shouldSummarize(usage: usage)
        guard shouldSummarize else { return }
        
        summaryState = .summarizing
        
        do {
            // Create summary
            let result = try await summaryService.createSummary(
                messageSets: messageSets,
                previousSummary: chat.contextSummary,
                modelConfig: modelConfig,
                keychain: keychain
            )
            
            // Get messages to exclude
            let excludeIds = await summaryService.getMessagesToExclude(messageSets: messageSets)
            
            // Apply summary to chat
            chat.applySummary(result, excludeMessageIds: excludeIds)
            
            // Calculate tokens saved
            let oldTokens = usage.totalTokens
            await updateContextUsage()
            let newTokens = contextUsage?.totalTokens ?? oldTokens
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
        
        // Build optimized context
        let builtContext = await contextBuilder.buildContext(
            chat: chat,
            messageSets: messageSets,
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
                        Task {
                            message.tokenCount = await self.tokenCounter.estimateTokens(fullText)
                        }
                        if let toolCalls = toolCalls {
                            message.toolCalls = try? JSONEncoder().encode(toolCalls)
                        }
                        try? self.modelContext.save()
                        
                        // Update context usage after response
                        await self.updateContextUsage()
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

