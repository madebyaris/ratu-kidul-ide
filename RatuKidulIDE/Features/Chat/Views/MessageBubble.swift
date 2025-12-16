import SwiftUI
import SwiftData

struct MessageBubble: View {
    let message: Message
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Model avatar/indicator
            Circle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(String(message.modelConfigId.prefix(1)).uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            
            VStack(alignment: .leading, spacing: 8) {
                // Model name
                Text(message.modelConfigId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Message content
                Text(message.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Error message if any
                if message.state == .error, let errorMessage = message.errorMessage {
                    Text("Error: \(errorMessage)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                // Streaming indicator
                if message.state == .streaming {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            Spacer()
            
            // Hover actions
            if isHovering {
                HStack(spacing: 8) {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
    }
}

