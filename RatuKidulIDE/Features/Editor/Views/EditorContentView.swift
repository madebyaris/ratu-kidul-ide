import SwiftUI

/// Content area that displays either the chat view or a code editor based on active tab
struct EditorContentView: View {
    @Bindable var tabManager: EditorTabManager
    let chatId: String?
    
    var body: some View {
        Group {
            if let activeTab = tabManager.activeTab {
                switch activeTab.type {
                case .chat:
                    // Show chat view
                    if let chatId = chatId {
                        ChatView(chatId: chatId)
                    } else {
                        EmptyChatPlaceholder()
                    }
                    
                case .file(let path, _):
                    // Show code editor - use id() to maintain separate state per file
                    FileEditorWrapper(
                        filePath: path,
                        tabManager: tabManager
                    )
                    .id(path) // Important: unique identity per file path
                }
            } else {
                // Fallback - should not happen
                Text("No tab selected")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Wrapper for the code editor that handles content binding
struct FileEditorWrapper: View {
    let filePath: String
    @Bindable var tabManager: EditorTabManager
    
    var body: some View {
        // Create a binding that reads/writes directly to tabManager
        let contentBinding = Binding<String>(
            get: { tabManager.fileContents[filePath] ?? "" },
            set: { newValue in
                tabManager.updateFileContent(path: filePath, content: newValue)
            }
        )
        
        CodeEditorView(
            filePath: filePath,
            content: contentBinding,
            onContentChange: { _ in
                // Content change is already handled by the binding's setter
            }
        )
    }
}

/// Placeholder shown when no chat is available
struct EmptyChatPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Chat Selected")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select or create a chat to start")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var tabManager = EditorTabManager()
        
        var body: some View {
            VStack(spacing: 0) {
                TabBarView(tabManager: tabManager)
                Divider()
                EditorContentView(tabManager: tabManager, chatId: nil)
            }
            .frame(width: 800, height: 600)
            .onAppear {
                // Add a test file
                tabManager.openFile(path: "/test/main.swift", name: "main.swift")
                tabManager.fileContents["/test/main.swift"] = """
                import Foundation
                
                func main() {
                    print("Hello, World!")
                }
                
                main()
                """
            }
        }
    }
    
    return PreviewWrapper()
}
