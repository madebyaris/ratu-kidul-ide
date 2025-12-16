import SwiftUI

/// View for displaying user prompts in the chat
struct UserMessageView: View {
    let prompt: String
    let timestamp: Date
    let tokenCount: Int
    
    @State private var isExpanded = true
    @State private var isHovering = false
    @AppStorage("chatFontSize") private var chatFontSize: Double = FontSettingsDefaults.chatFontSize
    
    // Collapse long prompts by default
    private let collapseThreshold = 500
    private var shouldShowCollapseButton: Bool {
        prompt.count > collapseThreshold
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Header with timestamp
            HStack {
                Spacer()
                
                Text(timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                if tokenCount > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(tokenCount) tokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Message bubble
            HStack {
                Spacer(minLength: 60)
                
                VStack(alignment: .trailing, spacing: 8) {
                    // Prompt content
                    Group {
                        if shouldShowCollapseButton && !isExpanded {
                            Text(String(prompt.prefix(collapseThreshold)) + "...")
                                .font(.system(size: chatFontSize))
                                .textSelection(.enabled)
                        } else {
                            Text(prompt)
                                .font(.system(size: chatFontSize))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Collapse/Expand button
                    if shouldShowCollapseButton {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                Text(isExpanded ? "Show less" : "Show more")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Hover actions
                    if isHovering {
                        HStack(spacing: 8) {
                            Button(action: copyToClipboard) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy")
                        }
                        .transition(.opacity)
                    }
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onHover { isHovering = $0 }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        UserMessageView(
            prompt: "Can you help me fix this bug?",
            timestamp: Date(),
            tokenCount: 8
        )
        
        UserMessageView(
            prompt: String(repeating: "This is a very long prompt that should be collapsed. ", count: 20),
            timestamp: Date(),
            tokenCount: 150
        )
    }
    .padding()
    .frame(width: 600)
}
