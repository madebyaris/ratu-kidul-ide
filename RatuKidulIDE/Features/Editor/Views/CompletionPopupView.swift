import SwiftUI

/// Popup view for displaying code completion suggestions
struct CompletionPopupView: View {
    let completions: [CompletionItem]
    @Binding var selectedIndex: Int
    let onSelect: (CompletionItem) -> Void
    
    var body: some View {
        if completions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(completions.enumerated()), id: \.element.id) { index, item in
                    CompletionItemRow(
                        item: item,
                        isSelected: index == selectedIndex
                    )
                    .onTapGesture {
                        onSelect(item)
                    }
                }
            }
            .frame(maxWidth: 400, maxHeight: 300)
            .background(.regularMaterial)
            .cornerRadius(8)
            .shadow(radius: 8)
        }
    }
}

/// Single completion item row
struct CompletionItemRow: View {
    let item: CompletionItem
    let isSelected: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Icon based on kind
            Image(systemName: iconName(for: item.kind))
                .foregroundStyle(iconColor(for: item.kind))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
    
    private func iconName(for kind: CompletionItemKind?) -> String {
        guard let kind = kind else { return "doc.text" }
        
        switch kind {
        case .method, .function:
            return "function"
        case .variable:
            return "variable"
        case .`class`:
            return "square.stack.3d.up"
        case .interface:
            return "square.dashed"
        case .property:
            return "tag"
        case .keyword:
            return "key"
        case .enum, .enumMember:
            return "list.bullet.rectangle"
        case .constant:
            return "number"
        case .`struct`:
            return "square.stack"
        case .module:
            return "cube.box"
        case .file:
            return "doc"
        case .folder:
            return "folder"
        default:
            return "doc.text"
        }
    }
    
    private func iconColor(for kind: CompletionItemKind?) -> Color {
        guard let kind = kind else { return .secondary }
        
        switch kind {
        case .method, .function:
            return .blue
        case .variable:
            return .orange
        case .`class`:
            return .purple
        case .interface:
            return .cyan
        case .property:
            return .green
        case .keyword:
            return .pink
        case .enum, .enumMember:
            return .indigo
        case .constant:
            return .yellow
        default:
            return .secondary
        }
    }
}

#Preview {
    CompletionPopupView(
        completions: [
            CompletionItem(label: "print", kind: .function, detail: "Print to console"),
            CompletionItem(label: "String", kind: .`class`, detail: "A Unicode string value"),
            CompletionItem(label: "count", kind: .property, detail: "The number of characters")
        ],
        selectedIndex: .constant(0),
        onSelect: { _ in }
    )
    .padding()
}
