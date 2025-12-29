import SwiftUI

/// Popover view for displaying hover documentation
struct HoverPopoverView: View {
    let hover: Hover
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch hover.contents {
            case .string(let text):
                Text(text)
                    .font(.body)
                
            case .markup(let markup):
                MarkdownText(markup.value)
                
            case .array(let markups):
                ForEach(Array(markups.enumerated()), id: \.offset) { _, markup in
                    MarkdownText(markup.value)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 400)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 8)
    }
}

/// Simple markdown text renderer (can be enhanced with full markdown support)
struct MarkdownText: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(parseMarkdown(text))
            .font(.body)
            .textSelection(.enabled)
    }
    
    private func parseMarkdown(_ text: String) -> AttributedString {
        // Simple markdown parsing - can be enhanced
        var attributed = AttributedString(text)
        
        // Bold
        if let range = attributed.range(of: "**") {
            // Simple implementation - can be enhanced
        }
        
        return attributed
    }
}

#Preview {
    HoverPopoverView(
        hover: Hover(
            contents: .markup(MarkupContent(
                kind: .markdown,
                value: "**Function**: `print(_:separator:terminator:)`\n\nPrints the items to the standard output."
            ))
        )
    )
    .padding()
}
