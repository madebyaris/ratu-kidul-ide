import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selectedProjectId: String?
    @Binding var selectedChatId: String?
    @Binding var showSettings: Bool
    var onFileOpen: ((String, String) -> Void)?  // (path, name) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    
    init(
        selectedProjectId: Binding<String?>,
        selectedChatId: Binding<String?>,
        showSettings: Binding<Bool>,
        onFileOpen: ((String, String) -> Void)? = nil
    ) {
        self._selectedProjectId = selectedProjectId
        self._selectedChatId = selectedChatId
        self._showSettings = showSettings
        self.onFileOpen = onFileOpen
    }
    
    var body: some View {
        Group {
            // File Explorer (only when project is selected)
            if let projectId = selectedProjectId,
               let project = projects.first(where: { $0.id == projectId }) {
                FileExplorerView(
                    projectPath: project.path ?? "",
                    onFileOpen: onFileOpen
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Empty state when no project
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    
                    Text("No Project Open")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Open a project to see files")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.03)) // Subtle darker background
        .navigationTitle("Files")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createNewChat) {
                    Image(systemName: "plus")
                }
                .help("New Chat")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                }
                .help("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
    
    private func createNewChat() {
        // If a project is selected, create chat for that project
        if let projectId = selectedProjectId,
           let project = projects.first(where: { $0.id == projectId }) {
            let chat = Chat()
            chat.project = project
            chat.title = "Chat - \(project.name)"
            modelContext.insert(chat)
            selectedChatId = chat.id
            try? modelContext.save()
        } else {
            // Create standalone chat
            let chat = Chat()
            modelContext.insert(chat)
            selectedChatId = chat.id
            try? modelContext.save()
        }
    }
}

