import SwiftUI

/// Tab bar component showing all open tabs
struct TabBarView: View {
    @Bindable var tabManager: EditorTabManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabManager.tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isActive: tabManager.activeTabId == tab.id,
                        tabManager: tabManager,
                        onSelect: {
                            tabManager.setActiveTab(id: tab.id)
                        },
                        onClose: {
                            tabManager.closeTab(id: tab.id)
                        }
                    )
                }
                
                Spacer()
            }
        }
        .frame(height: 36)
        .background(Color(.windowBackgroundColor))
    }
}

/// Individual tab item view
struct TabItemView: View {
    let tab: EditorTab
    let isActive: Bool
    @Bindable var tabManager: EditorTabManager
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Icon
            Image(systemName: tab.iconName)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
            
            // Title
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            
            // Modified indicator or close button
            if tab.canClose {
                Button(action: onClose) {
                    ZStack {
                        // Show dot when modified and not hovering
                        if tab.isModified && !isHovering {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                        } else {
                            // Show close button on hover
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(isHovering ? Color.primary : Color.clear)
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            } else if tab.type.isChat {
                // Chat tab shows a subtle indicator that it can't be closed
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tabBackground)
        .overlay(alignment: .bottom) {
            // Active indicator line
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            if tab.canClose {
                Button("Close") {
                    onClose()
                }
                
                Button("Close Others") {
                    tabManager.closeOtherTabs()
                }
                
                Button("Close All") {
                    tabManager.closeAllFileTabs()
                }
                
                Divider()
                
                if tab.isModified {
                    Button("Save") {
                        try? tabManager.saveFile(path: tab.id, content: tabManager.fileContents[tab.id] ?? "")
                    }
                }
                
                if case .file(let path, _) = tab.type {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                    }
                }
            }
        }
    }
    
    private var tabBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color(.controlBackgroundColor))
        } else if isHovering {
            return AnyShapeStyle(Color(.controlBackgroundColor).opacity(0.5))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }
    
    private var iconColor: Color {
        switch tab.type {
        case .chat:
            return .accentColor
        case .file(_, let name):
            return colorForFileExtension(name)
        }
    }
    
    private func colorForFileExtension(_ filename: String) -> Color {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        case "swift":
            return .orange
        case "js", "jsx":
            return .yellow
        case "ts", "tsx":
            return .blue
        case "py":
            return .blue
        case "rs":
            return .orange
        case "go":
            return .cyan
        case "html", "htm":
            return .red
        case "css", "scss":
            return .pink
        case "json":
            return .green
        case "md", "markdown":
            return .purple
        default:
            return .secondary
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var tabManager = EditorTabManager()
        
        var body: some View {
            VStack(spacing: 0) {
                TabBarView(tabManager: tabManager)
                Divider()
                Spacer()
            }
            .frame(width: 600, height: 400)
            .onAppear {
                tabManager.openFile(path: "/test/main.swift", name: "main.swift")
                tabManager.openFile(path: "/test/app.tsx", name: "app.tsx")
                tabManager.tabs[1].isModified = true
            }
        }
    }
    
    return PreviewWrapper()
}

