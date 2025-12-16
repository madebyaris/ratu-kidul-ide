import SwiftUI
import SwiftData

struct ProjectWorkspaceView: View {
    let projectId: String
    @Binding var selectedChatId: String?
    
    @Environment(\.modelContext) private var modelContext
    @State private var project: Project?
    
    var body: some View {
        Group {
            if let project = project {
                // Chat fills entire workspace (file explorer is now in sidebar)
                chatContentView(project: project)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Loading project...")
            }
        }
        .task {
            loadProject()
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
    
    @ViewBuilder
    private func chatContentView(project: Project) -> some View {
        // Chat view - fills entire space
        if let chatId = selectedChatId {
            ChatView(chatId: chatId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                Text("Ready to Chat")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start a conversation about your project")
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                Button("New Chat") {
                    createNewChat()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

