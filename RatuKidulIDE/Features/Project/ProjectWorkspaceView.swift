import SwiftUI
import SwiftData

struct ProjectWorkspaceView: View {
    let projectId: String
    @Binding var selectedChatId: String?
    @Bindable var tabManager: EditorTabManager
    
    @Environment(\.modelContext) private var modelContext
    @State private var project: Project?
    @State private var showSaveError: Bool = false
    @State private var saveErrorMessage: String = ""
    
    var body: some View {
        Group {
            if let _ = project {
                // Tabbed editor layout
                VStack(spacing: 0) {
                    // Search bar (when visible)
                    if tabManager.isSearchVisible {
                        SearchBarView(tabManager: tabManager)
                    }
                    
                    // Tab bar at top
                    TabBarView(tabManager: tabManager)
                    
                    Divider()
                    
                    // Content area - shows active tab content
                    EditorContentView(tabManager: tabManager, chatId: selectedChatId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView("Loading project...")
            }
        }
        .task {
            loadProject()
        }
        // Listen for keyboard shortcut notifications
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            saveActiveFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveAllFiles)) { _ in
            saveAllFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInFile)) { _ in
            tabManager.isSearchVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
            closeActiveTab()
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func loadProject() {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectId }
        )
        project = try? modelContext.fetch(descriptor).first
    }
    
    private func createNewChat() {
        guard let project = project else { return }
        
        let newChat = Chat()
        newChat.project = project
        newChat.title = "Chat - \(project.name)"
        modelContext.insert(newChat)
        try? modelContext.save()
        
        selectedChatId = newChat.id
    }
    
    private func saveActiveFile() {
        do {
            try tabManager.saveActiveFile()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
    
    private func saveAllFiles() {
        for tab in tabManager.unsavedTabs {
            if case .file(let path, _) = tab.type,
               let content = tabManager.fileContents[path] {
                do {
                    try tabManager.saveFile(path: path, content: content)
                } catch {
                    saveErrorMessage = "Failed to save \(tab.title): \(error.localizedDescription)"
                    showSaveError = true
                    return
                }
            }
        }
    }
    
    private func closeActiveTab() {
        if let activeTab = tabManager.activeTab, activeTab.canClose {
            tabManager.closeTab(id: activeTab.id)
        }
    }
    
    /// Open a file in the editor (called from FileExplorer)
    func openFile(path: String, name: String) {
        tabManager.openFile(path: path, name: name)
    }
}

// MARK: - Search Bar View

struct SearchBarView: View {
    @Bindable var tabManager: EditorTabManager
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search in file...", text: $tabManager.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    NotificationCenter.default.post(name: .findNext, object: nil)
                }
            
            if !tabManager.searchQuery.isEmpty {
                Button(action: {
                    tabManager.searchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .frame(height: 16)
            
            Button(action: {
                NotificationCenter.default.post(name: .findPrevious, object: nil)
            }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .help("Previous Match (⇧⌘G)")
            
            Button(action: {
                NotificationCenter.default.post(name: .findNext, object: nil)
            }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .help("Next Match (⌘G)")
            
            Spacer()
            
            Button(action: {
                tabManager.isSearchVisible = false
                tabManager.searchQuery = ""
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .onAppear {
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .escapeKey)) { _ in
            tabManager.isSearchVisible = false
        }
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    static let escapeKey = Notification.Name("escapeKey")
}
