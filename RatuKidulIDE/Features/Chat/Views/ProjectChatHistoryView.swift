import SwiftUI
import SwiftData

/// Popover view showing chat history for a specific project
struct ProjectChatHistoryView: View {
    let projectId: String
    @Binding var selectedChatId: String?
    @Binding var isPresented: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Query private var projectChats: [Chat]
    @State private var project: Project?
    
    init(projectId: String, selectedChatId: Binding<String?>, isPresented: Binding<Bool>) {
        self.projectId = projectId
        self._selectedChatId = selectedChatId
        self._isPresented = isPresented
        
        // Query chats for this project
        _projectChats = Query(
            filter: #Predicate<Chat> { chat in
                chat.project?.id == projectId
            },
            sort: \Chat.updatedAt,
            order: .reverse
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Chat History")
                    .font(.headline)
                
                Spacer()
                
                Button(action: createNewChat) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Chat")
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // Chat list
            if projectChats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    
                    Text("No chats yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button("Start New Chat") {
                        createNewChat()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(projectChats) { chat in
                            ChatHistoryRow(
                                chat: chat,
                                isSelected: selectedChatId == chat.id,
                                onSelect: {
                                    selectedChatId = chat.id
                                    isPresented = false
                                },
                                onDelete: {
                                    deleteChat(chat)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 280, height: 350)
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
        guard let project = project else {
            // Try to load project first
            loadProject()
            guard let project = project else { return }
            createChatFor(project)
            return
        }
        createChatFor(project)
    }
    
    private func createChatFor(_ project: Project) {
        let newChat = Chat()
        newChat.project = project
        newChat.title = "Chat - \(project.name)"
        modelContext.insert(newChat)
        try? modelContext.save()
        
        selectedChatId = newChat.id
        isPresented = false
    }
    
    private func deleteChat(_ chat: Chat) {
        // If deleting the selected chat, clear selection
        if selectedChatId == chat.id {
            selectedChatId = nil
        }
        
        modelContext.delete(chat)
        try? modelContext.save()
    }
}

// MARK: - Chat History Row

struct ChatHistoryRow: View {
    let chat: Chat
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    // Static relative time - computed once, not live-updating
    private var relativeTime: String {
        let date = chat.updatedAt ?? chat.createdAt
        return date.relativeTimeString()
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "message")
                .foregroundStyle(isSelected ? .white : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title ?? "New Chat")
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            
            Spacer()
            
            // Delete button on hover
            if isHovering && !isSelected {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete Chat")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : (isHovering ? Color(.selectedContentBackgroundColor).opacity(0.3) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Date Extension for Static Relative Time

extension Date {
    /// Returns a static relative time string (no live updates)
    func relativeTimeString() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        
        // Future dates
        if interval < 0 {
            return "just now"
        }
        
        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        let months = days / 30
        let years = days / 365
        
        if seconds < 60 {
            return "just now"
        } else if minutes == 1 {
            return "1 minute ago"
        } else if minutes < 60 {
            return "\(minutes) minutes ago"
        } else if hours == 1 {
            return "1 hour ago"
        } else if hours < 24 {
            return "\(hours) hours ago"
        } else if days == 1 {
            return "yesterday"
        } else if days < 7 {
            return "\(days) days ago"
        } else if weeks == 1 {
            return "1 week ago"
        } else if weeks < 4 {
            return "\(weeks) weeks ago"
        } else if months == 1 {
            return "1 month ago"
        } else if months < 12 {
            return "\(months) months ago"
        } else if years == 1 {
            return "1 year ago"
        } else {
            return "\(years) years ago"
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectChatHistoryView(
        projectId: "preview-project",
        selectedChatId: .constant(nil),
        isPresented: .constant(true)
    )
}

