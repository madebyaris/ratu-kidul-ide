import SwiftUI
import SwiftData

/// View for displaying AI responses in the chat
struct AIResponseView: View {
    let message: Message
    
    @State private var isHovering = false
    @Query private var modelConfigs: [ModelConfig]
    
    private var modelName: String {
        modelConfigs.first { $0.id == message.modelConfigId }?.displayName ?? message.modelConfigId
    }
    
    private var modelInitial: String {
        String(modelName.prefix(1)).uppercased()
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Model avatar
            Circle()
                .fill(avatarColor)
                .frame(width: 32, height: 32)
                .overlay {
                    if message.state == .streaming {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Text(modelInitial)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                }
            
            VStack(alignment: .leading, spacing: 8) {
                // Model name and status
                HStack(spacing: 8) {
                    Text(modelName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    if message.state == .streaming {
                        Text("Thinking...")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    if let tokenCount = message.tokenCount, message.state == .complete {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(tokenCount) tokens")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Spacer()
                    
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                // Response content
                Group {
                    switch message.state {
                    case .streaming:
                        VStack(alignment: .leading, spacing: 8) {
                            if !message.text.isEmpty {
                                MarkdownText(message.text)
                            }
                            StreamingIndicator()
                        }
                        
                    case .complete:
                        MarkdownText(message.text)
                        
                    case .error:
                        VStack(alignment: .leading, spacing: 8) {
                            if !message.text.isEmpty {
                                MarkdownText(message.text)
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(message.errorMessage ?? "An error occurred")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        
                    case .cancelled:
                        VStack(alignment: .leading, spacing: 8) {
                            if !message.text.isEmpty {
                                MarkdownText(message.text)
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle")
                                    .foregroundStyle(.orange)
                                Text("Response cancelled")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Hover actions
                if isHovering && message.state == .complete {
                    HStack(spacing: 12) {
                        Button(action: copyToClipboard) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        
                        // Future: Add regenerate, edit, etc.
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(12)
        .background(Color(.textBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
    }
    
    private var avatarColor: Color {
        // Generate consistent color based on model ID
        let hash = message.modelConfigId.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.7)
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicator: View {
    @State private var dotCount = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(dotCount > index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}

// MARK: - Markdown Text View

struct MarkdownText: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        // For now, simple text rendering
        // TODO: Add proper markdown rendering with code highlighting
        Text(text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AIResponseView(message: {
            let msg = Message(modelConfigId: "openai/gpt-4", role: .assistant)
            msg.text = "Here's how you can fix that bug:\n\n1. First, check the input validation\n2. Then update the error handling\n3. Finally, add unit tests"
            msg.state = .complete
            msg.tokenCount = 45
            return msg
        }())
        
        AIResponseView(message: {
            let msg = Message(modelConfigId: "anthropic/claude-3", role: .assistant)
            msg.text = "Let me think about this..."
            msg.state = .streaming
            return msg
        }())
    }
    .padding()
    .frame(width: 600)
}

