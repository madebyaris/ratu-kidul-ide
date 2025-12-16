import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("lastProjectId") private var lastProjectId: String = ""
    @AppStorage("lastChatId") private var lastChatId: String = ""
    @State private var selectedProjectId: String?
    @State private var selectedChatId: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showSettings = false
    @State private var hasRestoredState = false
    @State private var showChatHistory = false
    
    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil // system
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedProjectId: $selectedProjectId,
                selectedChatId: $selectedChatId,
                showSettings: $showSettings
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 350)
        } detail: {
            Group {
                if let projectId = selectedProjectId {
                    ProjectWorkspaceView(
                        projectId: projectId,
                        selectedChatId: $selectedChatId
                    )
                } else if let chatId = selectedChatId {
                    ChatView(chatId: chatId)
                } else {
                    EmptyStateView { projectId in
                        selectedProjectId = projectId
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                // Chat history button (only show when project is selected)
                if selectedProjectId != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            showChatHistory.toggle()
                        }) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .help("Chat History")
                        .popover(isPresented: $showChatHistory, arrowEdge: .bottom) {
                            if let projectId = selectedProjectId {
                                ProjectChatHistoryView(
                                    projectId: projectId,
                                    selectedChatId: $selectedChatId,
                                    isPresented: $showChatHistory
                                )
                            }
                        }
                    }
                }
            }
            .toolbar(removing: .sidebarToggle)
        }
        .navigationTitle("Ratu Kidul IDE")
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettings"))) { _ in
            showSettings = true
        }
        .onAppear {
            restoreLastState()
        }
        .onChange(of: selectedProjectId) { _, newValue in
            if let projectId = newValue {
                lastProjectId = projectId
                createOrLoadChatForProject(projectId)
            }
        }
        .onChange(of: selectedChatId) { _, newValue in
            if let chatId = newValue {
                lastChatId = chatId
            }
        }
    }
    
    private func restoreLastState() {
        guard !hasRestoredState else { return }
        hasRestoredState = true
        
        // Restore last project if available
        if !lastProjectId.isEmpty {
            // Verify project still exists
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate { $0.id == lastProjectId }
            )
            if let _ = try? modelContext.fetch(descriptor).first {
                selectedProjectId = lastProjectId
            }
        }
        
        // Restore last chat if available
        if !lastChatId.isEmpty {
            let descriptor = FetchDescriptor<Chat>(
                predicate: #Predicate { $0.id == lastChatId }
            )
            if let _ = try? modelContext.fetch(descriptor).first {
                selectedChatId = lastChatId
            }
        }
    }
    
    private func createOrLoadChatForProject(_ projectId: String) {
        // First try to find an existing chat for this project
        let descriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { chat in
                chat.project?.id == projectId
            },
            sortBy: [SortDescriptor(\Chat.updatedAt, order: .reverse)]
        )
        
        if let existingChat = try? modelContext.fetch(descriptor).first {
            selectedChatId = existingChat.id
            return
        }
        
        // No existing chat, create a new one
        let projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectId }
        )
        
        guard let project = try? modelContext.fetch(projectDescriptor).first else { return }
        
        let newChat = Chat()
        newChat.project = project
        newChat.title = "Chat - \(project.name)"
        modelContext.insert(newChat)
        try? modelContext.save()
        
        selectedChatId = newChat.id
    }
}

