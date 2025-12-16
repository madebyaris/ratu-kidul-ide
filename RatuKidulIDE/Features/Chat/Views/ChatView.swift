import SwiftUI
import SwiftData

struct ChatView: View {
    let chatId: String
    
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ChatViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                ChatContentView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let vm = ChatViewModel(chatId: chatId, modelContext: modelContext)
            viewModel = vm
            await vm.loadChat()
        }
    }
}

struct ChatContentView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var inputHeight: CGFloat = 120
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Messages list - fills available space, with padding for input
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            // Iterate through conversation turns (user prompt + AI responses)
                            ForEach(viewModel.conversationTurns) { turn in
                                ConversationTurnView(turn: turn)
                                    .id(turn.id)
                            }
                            
                            // Bottom spacer to ensure content doesn't hide behind input
                            Color.clear
                                .frame(height: inputHeight + 20)
                        }
                        .padding()
                        // Prevent large empty "dead zone" above messages by top-aligning expanded content
                        //.frame(minHeight: max(0, geometry.size.height - inputHeight), alignment: .top)
                        //.frame(maxWidth: .infinity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onChange(of: viewModel.conversationTurns.count) { _, _ in
                        withAnimation {
                            if let lastTurn = viewModel.conversationTurns.last {
                                proxy.scrollTo(lastTurn.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input area - fixed at bottom
                VStack(spacing: 0) {
                    // Summary status indicator
                    if viewModel.summaryState.isActive {
                        SummaryStatusBar(state: viewModel.summaryState)
                    }
                    
                    Divider()
                    ChatInputView(
                        text: $viewModel.inputText,
                        attachments: $viewModel.attachments,
                        selectedModels: $viewModel.selectedModels,
                        isLoading: viewModel.isLoading,
                        contextUsage: viewModel.contextUsage,
                        onSend: {
                            Task {
                                await viewModel.sendMessage()
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { inputGeometry in
                            Color.clear.preference(
                                key: InputHeightPreferenceKey.self,
                                value: inputGeometry.size.height
                            )
                        }
                    )
                }
                .frame(width: geometry.size.width)
                .background(Color(.windowBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(InputHeightPreferenceKey.self) { height in
            inputHeight = height
        }
    }
}

// MARK: - Conversation Turn View

/// Displays a single conversation turn: user prompt followed by AI response(s)
struct ConversationTurnView: View {
    let turn: ConversationTurn
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // User prompt (displayed first, at the top)
            if !turn.userPrompt.isEmpty {
                UserMessageView(
                    prompt: turn.userPrompt,
                    timestamp: turn.timestamp,
                    tokenCount: turn.userPromptTokens
                )
            }
            
            // AI responses (displayed below the user prompt)
            ForEach(turn.responses.filter { $0.role == .assistant }) { message in
                AIResponseView(message: message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Summary Status Bar

struct SummaryStatusBar: View {
    let state: SummaryState
    
    var body: some View {
        HStack(spacing: 8) {
            if state.isActive {
                ProgressView()
                    .scaleEffect(0.7)
            }
            
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
    }
}

// MARK: - Preference Key

private struct InputHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 120
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Legacy Support (keep for compatibility)

struct MessageSetView: View {
    let messageSet: MessageSet
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(messageSet.messages) { message in
                MessageBubble(message: message)
            }
        }
    }
}

