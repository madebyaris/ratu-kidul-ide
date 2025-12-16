import Foundation

/// Type of tab in the editor
enum EditorTabType: Equatable, Hashable {
    case chat                              // Permanent chat tab, cannot be closed
    case file(path: String, name: String)  // Closable file tab
    
    var isChat: Bool {
        if case .chat = self { return true }
        return false
    }
    
    var filePath: String? {
        if case .file(let path, _) = self { return path }
        return nil
    }
    
    var fileName: String? {
        if case .file(_, let name) = self { return name }
        return nil
    }
}

/// Represents a single tab in the editor
struct EditorTab: Identifiable, Equatable, Hashable {
    let id: String
    let type: EditorTabType
    var isModified: Bool = false  // Show dot indicator for unsaved changes
    
    /// Display title for the tab
    var title: String {
        switch type {
        case .chat:
            return "Chat"
        case .file(_, let name):
            return name
        }
    }
    
    /// Whether this tab can be closed
    var canClose: Bool {
        !type.isChat
    }
    
    /// Icon name for the tab
    var iconName: String {
        switch type {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .file(_, let name):
            return iconForFileExtension(name)
        }
    }
    
    /// Get appropriate icon based on file extension
    private func iconForFileExtension(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        case "swift":
            return "swift"
        case "js", "jsx":
            return "doc.text"
        case "ts", "tsx":
            return "doc.text"
        case "py":
            return "chevron.left.forwardslash.chevron.right"
        case "rs":
            return "gearshape"
        case "go":
            return "chevron.left.forwardslash.chevron.right"
        case "java", "kt":
            return "cup.and.saucer"
        case "c", "cpp", "h", "hpp":
            return "c.square"
        case "html", "htm":
            return "globe"
        case "css", "scss", "sass":
            return "paintbrush"
        case "json":
            return "curlybraces"
        case "xml":
            return "chevron.left.forwardslash.chevron.right"
        case "yml", "yaml":
            return "list.bullet.indent"
        case "md", "markdown":
            return "doc.richtext"
        case "txt":
            return "doc.text"
        case "sh", "bash", "zsh":
            return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return "photo"
        case "pdf":
            return "doc.fill"
        default:
            return "doc"
        }
    }
    
    // MARK: - Factory Methods
    
    /// Create a chat tab
    static func chatTab() -> EditorTab {
        EditorTab(id: "chat", type: .chat)
    }
    
    /// Create a file tab
    static func fileTab(path: String, name: String) -> EditorTab {
        EditorTab(id: path, type: .file(path: path, name: name))
    }
}

