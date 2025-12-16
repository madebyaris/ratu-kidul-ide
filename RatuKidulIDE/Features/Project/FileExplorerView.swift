import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FileExplorerView: View {
    let projectPath: String
    var onFileOpen: ((String, String) -> Void)?  // (path, name) -> Void
    
    @State private var rootNode: FileNode?
    @State private var expandedFolders: Set<String> = []
    @State private var selectedFile: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // File operation states
    @State private var isCreatingNewFile = false
    @State private var isCreatingNewFolder = false
    @State private var newItemName = ""
    @State private var newItemParentPath: String?
    @State private var renamingNodeId: String?
    @State private var renameText = ""
    @State private var showDeleteConfirmation = false
    @State private var nodeToDelete: FileNode?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack(spacing: 8) {
                Text("Files")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // New File button
                Button(action: {
                    startCreatingNewFile(in: projectPath)
                }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("New File")
                
                // New Folder button
                Button(action: {
                    startCreatingNewFolder(in: projectPath)
                }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("New Folder")
                
                Button(action: refreshFiles) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading files...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        refreshFiles()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let rootNode = rootNode {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Show new item input at root level
                        if let parentPath = newItemParentPath, parentPath == projectPath {
                            NewItemInputRow(
                                name: $newItemName,
                                isFolder: isCreatingNewFolder,
                                onSubmit: { createNewItem() },
                                onCancel: { cancelNewItem() }
                            )
                            .padding(.leading, 8)
                        }
                        
                        ForEach(rootNode.children ?? []) { node in
                            FileNodeView(
                                node: node,
                                depth: 0,
                                expandedFolders: $expandedFolders,
                                selectedFile: $selectedFile,
                                renamingNodeId: $renamingNodeId,
                                renameText: $renameText,
                                newItemParentPath: $newItemParentPath,
                                newItemName: $newItemName,
                                isCreatingNewFile: $isCreatingNewFile,
                                isCreatingNewFolder: $isCreatingNewFolder,
                                onRename: { node, newName in
                                    renameItem(node: node, to: newName)
                                },
                                onDelete: { node in
                                    nodeToDelete = node
                                    showDeleteConfirmation = true
                                },
                                onCreateFile: { parentPath in
                                    startCreatingNewFile(in: parentPath)
                                },
                                onCreateFolder: { parentPath in
                                    startCreatingNewFolder(in: parentPath)
                                },
                                onRevealInFinder: { path in
                                    revealInFinder(path: path)
                                },
                                onFileOpen: { path, name in
                                    onFileOpen?(path, name)
                                },
                                onNewItemSubmit: { createNewItem() },
                                onNewItemCancel: { cancelNewItem() }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                VStack {
                    Image(systemName: "folder")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No files found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.windowBackgroundColor).opacity(0.95))
        .task {
            await loadFiles()
        }
        .alert("Delete Item", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                nodeToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let node = nodeToDelete {
                    deleteItem(node: node)
                }
                nodeToDelete = nil
            }
        } message: {
            if let node = nodeToDelete {
                if node.isDirectory {
                    Text("Are you sure you want to delete the folder \"\(node.name)\" and all its contents? This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete \"\(node.name)\"? This action cannot be undone.")
                }
            }
        }
    }
    
    // MARK: - File Operations
    
    private func startCreatingNewFile(in parentPath: String) {
        cancelNewItem()
        isCreatingNewFile = true
        isCreatingNewFolder = false
        newItemParentPath = parentPath
        newItemName = ""
        
        // Expand the parent folder if it's not the root
        if parentPath != projectPath {
            expandedFolders.insert(parentPath)
        }
    }
    
    private func startCreatingNewFolder(in parentPath: String) {
        cancelNewItem()
        isCreatingNewFolder = true
        isCreatingNewFile = false
        newItemParentPath = parentPath
        newItemName = ""
        
        // Expand the parent folder if it's not the root
        if parentPath != projectPath {
            expandedFolders.insert(parentPath)
        }
    }
    
    private func cancelNewItem() {
        isCreatingNewFile = false
        isCreatingNewFolder = false
        newItemParentPath = nil
        newItemName = ""
    }
    
    private func createNewItem() {
        guard let parentPath = newItemParentPath, !newItemName.isEmpty else {
            cancelNewItem()
            return
        }
        
        let fileManager = FileManager.default
        let newPath = (parentPath as NSString).appendingPathComponent(newItemName)
        
        do {
            if isCreatingNewFolder {
                try fileManager.createDirectory(atPath: newPath, withIntermediateDirectories: false)
            } else {
                // Create empty file
                fileManager.createFile(atPath: newPath, contents: nil)
            }
            
            cancelNewItem()
            refreshFiles()
        } catch {
            print("Failed to create item: \(error)")
            // Could show an alert here
        }
    }
    
    private func renameItem(node: FileNode, to newName: String) {
        guard !newName.isEmpty, newName != node.name else {
            renamingNodeId = nil
            return
        }
        
        let fileManager = FileManager.default
        let parentPath = (node.path as NSString).deletingLastPathComponent
        let newPath = (parentPath as NSString).appendingPathComponent(newName)
        
        do {
            try fileManager.moveItem(atPath: node.path, toPath: newPath)
            renamingNodeId = nil
            refreshFiles()
        } catch {
            print("Failed to rename item: \(error)")
            renamingNodeId = nil
        }
    }
    
    private func deleteItem(node: FileNode) {
        let fileManager = FileManager.default
        
        do {
            try fileManager.removeItem(atPath: node.path)
            refreshFiles()
        } catch {
            print("Failed to delete item: \(error)")
        }
    }
    
    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    // MARK: - File Loading
    
    private func refreshFiles() {
        Task {
            await loadFiles()
        }
    }
    
    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        
        guard !projectPath.isEmpty else {
            errorMessage = "No project path set"
            isLoading = false
            return
        }
        
        let url = URL(fileURLWithPath: projectPath)
        
        do {
            rootNode = try await buildFileTree(at: url, depth: 0)
            isLoading = false
        } catch {
            errorMessage = "Failed to load files: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func buildFileTree(at url: URL, depth: Int) async throws -> FileNode {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey, .fileSizeKey]
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileExplorerError.pathNotFound
        }
        
        let name = url.lastPathComponent
        let isDir = isDirectory.boolValue
        
        var children: [FileNode]? = nil
        
        if isDir && depth < 5 { // Limit depth to prevent performance issues
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
            
            var childNodes: [FileNode] = []
            for childURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                // Skip common non-essential directories
                let name = childURL.lastPathComponent
                if name == "node_modules" || name == ".git" || name == ".build" || name == "Pods" || name == "DerivedData" {
                    continue
                }
                
                let childNode = try await buildFileTree(at: childURL, depth: depth + 1)
                childNodes.append(childNode)
            }
            
            // Sort: directories first, then files
            children = childNodes.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        
        return FileNode(
            id: url.path,
            name: name,
            path: url.path,
            isDirectory: isDir,
            children: children
        )
    }
}

// MARK: - FileNode Model

struct FileNode: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]?
}

// MARK: - New Item Input Row

struct NewItemInputRow: View {
    @Binding var name: String
    let isFolder: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isFolder ? "folder.badge.plus" : "doc.badge.plus")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            
            TextField(isFolder ? "New folder name" : "New file name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onCancel)
            
            Button(action: onSubmit) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .disabled(name.isEmpty)
            
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.accentColor.opacity(0.1))
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - FileNodeView

struct FileNodeView: View {
    let node: FileNode
    let depth: Int
    @Binding var expandedFolders: Set<String>
    @Binding var selectedFile: String?
    @Binding var renamingNodeId: String?
    @Binding var renameText: String
    @Binding var newItemParentPath: String?
    @Binding var newItemName: String
    @Binding var isCreatingNewFile: Bool
    @Binding var isCreatingNewFolder: Bool
    
    let onRename: (FileNode, String) -> Void
    let onDelete: (FileNode) -> Void
    let onCreateFile: (String) -> Void
    let onCreateFolder: (String) -> Void
    let onRevealInFinder: (String) -> Void
    let onFileOpen: (String, String) -> Void  // (path, name) -> Void
    let onNewItemSubmit: () -> Void
    let onNewItemCancel: () -> Void
    
    @FocusState private var isRenameFocused: Bool
    
    private var isExpanded: Bool {
        expandedFolders.contains(node.id)
    }
    
    private var isRenaming: Bool {
        renamingNodeId == node.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Node row
            if isRenaming {
                // Rename mode
                HStack(spacing: 4) {
                    // Indentation
                    ForEach(0..<depth, id: \.self) { _ in
                        Color.clear.frame(width: 16)
                    }
                    
                    // Expand indicator space
                    if node.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    } else {
                        Color.clear.frame(width: 12)
                    }
                    
                    // Icon
                    Image(systemName: iconForFile(node))
                        .font(.system(size: 14))
                        .foregroundStyle(colorForFile(node))
                        .frame(width: 18)
                    
                    // Rename text field
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isRenameFocused)
                        .onSubmit {
                            onRename(node, renameText)
                        }
                        .onExitCommand {
                            renamingNodeId = nil
                        }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.accentColor.opacity(0.2))
                .onAppear {
                    renameText = node.name
                    isRenameFocused = true
                }
            } else {
                // Normal mode
                Button(action: {
                    if node.isDirectory {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isExpanded {
                                expandedFolders.remove(node.id)
                            } else {
                                expandedFolders.insert(node.id)
                            }
                        }
                    } else {
                        selectedFile = node.path
                        // Open file in editor tab
                        onFileOpen(node.path, node.name)
                    }
                }) {
                    HStack(spacing: 4) {
                        // Indentation
                        ForEach(0..<depth, id: \.self) { _ in
                            Color.clear.frame(width: 16)
                        }
                        
                        // Expand/collapse indicator for directories
                        if node.isDirectory {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                        } else {
                            Color.clear.frame(width: 12)
                        }
                        
                        // File/folder icon
                        Image(systemName: iconForFile(node))
                            .font(.system(size: 14))
                            .foregroundStyle(colorForFile(node))
                            .frame(width: 18)
                        
                        // Name
                        Text(node.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(selectedFile == node.path ? Color.accentColor.opacity(0.2) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    // Context menu
                    if node.isDirectory {
                        Button {
                            onCreateFile(node.path)
                        } label: {
                            Label("New File", systemImage: "doc.badge.plus")
                        }
                        
                        Button {
                            onCreateFolder(node.path)
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        
                        Divider()
                    }
                    
                    Button {
                        renamingNodeId = node.id
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        onDelete(node)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    Divider()
                    
                    Button {
                        onRevealInFinder(node.path)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
            }
            
            // Children (including new item input)
            if node.isDirectory && isExpanded {
                // Show new item input if creating in this folder
                if let parentPath = newItemParentPath, parentPath == node.path {
                    NewItemInputRow(
                        name: $newItemName,
                        isFolder: isCreatingNewFolder,
                        onSubmit: onNewItemSubmit,
                        onCancel: onNewItemCancel
                    )
                    .padding(.leading, CGFloat((depth + 1) * 16 + 8))
                }
                
                if let children = node.children {
                    ForEach(children) { child in
                        FileNodeView(
                            node: child,
                            depth: depth + 1,
                            expandedFolders: $expandedFolders,
                            selectedFile: $selectedFile,
                            renamingNodeId: $renamingNodeId,
                            renameText: $renameText,
                            newItemParentPath: $newItemParentPath,
                            newItemName: $newItemName,
                            isCreatingNewFile: $isCreatingNewFile,
                            isCreatingNewFolder: $isCreatingNewFolder,
                            onRename: onRename,
                            onDelete: onDelete,
                            onCreateFile: onCreateFile,
                            onCreateFolder: onCreateFolder,
                            onRevealInFinder: onRevealInFinder,
                            onFileOpen: onFileOpen,
                            onNewItemSubmit: onNewItemSubmit,
                            onNewItemCancel: onNewItemCancel
                        )
                    }
                }
            }
        }
    }
    
    private func iconForFile(_ node: FileNode) -> String {
        if node.isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        
        let ext = (node.name as NSString).pathExtension.lowercased()
        
        switch ext {
        case "swift":
            return "swift"
        case "js", "jsx", "ts", "tsx":
            return "doc.text"
        case "json":
            return "curlybraces"
        case "md", "markdown":
            return "doc.richtext"
        case "html", "htm":
            return "globe"
        case "css", "scss", "sass":
            return "paintbrush"
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return "photo"
        case "py":
            return "chevron.left.forwardslash.chevron.right"
        case "rs":
            return "gearshape"
        case "yml", "yaml":
            return "list.bullet.indent"
        case "txt":
            return "doc.text"
        case "pdf":
            return "doc.fill"
        default:
            return "doc"
        }
    }
    
    private func colorForFile(_ node: FileNode) -> Color {
        if node.isDirectory {
            return .blue
        }
        
        let ext = (node.name as NSString).pathExtension.lowercased()
        
        switch ext {
        case "swift":
            return .orange
        case "js", "jsx":
            return .yellow
        case "ts", "tsx":
            return .blue
        case "json":
            return .green
        case "md", "markdown":
            return .purple
        case "html", "htm":
            return .red
        case "css", "scss", "sass":
            return .pink
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return .teal
        case "py":
            return .blue
        case "rs":
            return .orange
        default:
            return .secondary
        }
    }
}

// MARK: - Error Types

enum FileExplorerError: Error {
    case pathNotFound
    case accessDenied
}
