# Technical Specification

## Ratu Kidul IDE — Native macOS AI IDE

**Version:** 1.0  
**Date:** December 16, 2025  
**Status:** Draft  
**Author:** Development Team

---

## 1. Overview

This document specifies the technical architecture for migrating Chorus from a Tauri/React application to a native SwiftUI macOS application while preserving all functionality and improving performance.

### 1.1 Current Stack (Chorus)

| Layer | Technology |
|-------|------------|
| Frontend | React 18, TypeScript, TailwindCSS |
| State | TanStack Query, Zustand |
| Runtime | Tauri 2.x (Rust) |
| Database | SQLite (tauri-plugin-sql) |
| UI Components | Radix UI, Shadcn/ui |
| Build | Vite, pnpm |

### 1.2 Target Stack (Ratu Kidul)

| Layer | Technology |
|-------|------------|
| UI Framework | SwiftUI 5+ (macOS 14+) |
| App Lifecycle | SwiftUI App protocol |
| Data Persistence | SwiftData + SQLite.swift |
| Networking | URLSession, async/await |
| Secure Storage | Keychain Services |
| Concurrency | Swift Concurrency (actors) |
| Build | Xcode 15+, Swift Package Manager |

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Ratu Kidul IDE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Presentation Layer                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │   │
│  │  │  MainWindow │  │ QuickChat   │  │    Settings     │  │   │
│  │  │   (SwiftUI) │  │  (NSPanel)  │  │   (SwiftUI)     │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Application Layer                      │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │   │
│  │  │ ChatService│  │ModelService│  │  ToolsetManager    │ │   │
│  │  └────────────┘  └────────────┘  └────────────────────┘ │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │   │
│  │  │ProjectSvc  │  │AttachmentSvc│ │  KeychainService   │ │   │
│  │  └────────────┘  └────────────┘  └────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                      Domain Layer                         │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │   │
│  │  │   Models   │  │  Providers │  │     Toolsets       │ │   │
│  │  │ (Entities) │  │ (Protocol) │  │    (Protocol)      │ │   │
│  │  └────────────┘  └────────────┘  └────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Infrastructure Layer                     │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │   │
│  │  │ SwiftData  │  │  Keychain  │  │   MCP Runtime      │ │   │
│  │  │ Repository │  │  Storage   │  │   (Process)        │ │   │
│  │  └────────────┘  └────────────┘  └────────────────────┘ │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │   │
│  │  │ FileSystem │  │  Network   │  │   Notifications    │ │   │
│  │  │  Access    │  │  Client    │  │   (UNUserNotif)    │ │   │
│  │  └────────────┘  └────────────┘  └────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Module Structure

```
RatuKidulIDE/
├── App/
│   ├── RatuKidulApp.swift          # @main entry point
│   ├── AppDelegate.swift           # NSApplicationDelegate
│   └── AppState.swift              # Global app state
├── Features/
│   ├── Chat/
│   │   ├── Views/
│   │   │   ├── ChatView.swift
│   │   │   ├── MessageView.swift
│   │   │   ├── MessageBubble.swift
│   │   │   └── ChatInputView.swift
│   │   ├── ViewModels/
│   │   │   └── ChatViewModel.swift
│   │   └── Models/
│   │       └── ChatModels.swift
│   ├── QuickChat/
│   │   ├── QuickChatPanel.swift    # NSPanel wrapper
│   │   └── QuickChatView.swift
│   ├── Projects/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   └── Models/
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── APIKeysView.swift
│   │   ├── ModelsView.swift
│   │   └── ToolsetsView.swift
│   └── Sidebar/
│       ├── SidebarView.swift
│       └── ProjectListView.swift
├── Core/
│   ├── Providers/
│   │   ├── AIProvider.swift        # Protocol
│   │   ├── AnthropicProvider.swift
│   │   ├── OpenAIProvider.swift
│   │   ├── GoogleProvider.swift
│   │   ├── GrokProvider.swift
│   │   ├── OpenRouterProvider.swift
│   │   ├── PerplexityProvider.swift
│   │   ├── OllamaProvider.swift
│   │   └── LMStudioProvider.swift
│   ├── MCP/
│   │   ├── MCPClient.swift
│   │   ├── MCPTransport.swift
│   │   └── MCPToolset.swift
│   ├── Toolsets/
│   │   ├── Toolset.swift           # Protocol
│   │   ├── FilesToolset.swift
│   │   ├── TerminalToolset.swift
│   │   ├── WebToolset.swift
│   │   ├── GitHubToolset.swift
│   │   └── CustomToolset.swift
│   └── Services/
│       ├── ChatService.swift
│       ├── ModelService.swift
│       ├── ProjectService.swift
│       ├── AttachmentService.swift
│       └── KeychainService.swift
├── Data/
│   ├── Models/
│   │   ├── Chat.swift
│   │   ├── Message.swift
│   │   ├── Project.swift
│   │   ├── Attachment.swift
│   │   ├── Model.swift
│   │   └── ModelConfig.swift
│   ├── Repositories/
│   │   ├── ChatRepository.swift
│   │   ├── MessageRepository.swift
│   │   └── ProjectRepository.swift
│   └── Migrations/
│       └── DatabaseMigrator.swift
├── Shared/
│   ├── Extensions/
│   ├── Utilities/
│   ├── Components/
│   │   ├── CodeBlock.swift
│   │   ├── MarkdownView.swift
│   │   └── LoadingIndicator.swift
│   └── Theme/
│       └── Theme.swift
└── Resources/
    ├── Assets.xcassets
    ├── Prompts/
    └── Localizable.strings
```

---

## 3. Data Layer

### 3.1 SwiftData Models

```swift
import SwiftData

@Model
final class Chat {
    @Attribute(.unique) var id: String
    var title: String?
    var createdAt: Date
    var updatedAt: Date?
    var isPinned: Bool
    var isQuickChat: Bool
    var isNewChat: Bool
    var summary: String?
    
    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message]
    
    @Relationship(inverse: \Project.chats)
    var project: Project?
    
    @Relationship
    var parentChat: Chat?
    
    init(id: String = UUID().uuidString) {
        self.id = id
        self.createdAt = Date()
        self.isPinned = false
        self.isQuickChat = false
        self.isNewChat = true
        self.messages = []
    }
}

@Model
final class Message {
    @Attribute(.unique) var id: String
    var text: String
    var modelConfigId: String
    var createdAt: Date
    var state: MessageState
    var errorMessage: String?
    var isReview: Bool
    var toolCalls: Data?      // JSON encoded
    var toolResults: Data?    // JSON encoded
    
    @Relationship
    var chat: Chat?
    
    @Relationship
    var messageSet: MessageSet?
    
    @Relationship(deleteRule: .nullify)
    var attachments: [Attachment]
    
    enum MessageState: String, Codable {
        case streaming
        case complete
        case error
        case cancelled
    }
}

@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isCollapsed: Bool
    var contextText: String?
    var magicProjectsEnabled: Bool
    
    @Relationship(deleteRule: .cascade)
    var chats: [Chat]
    
    @Relationship
    var attachments: [Attachment]
}

@Model
final class ModelConfig {
    @Attribute(.unique) var id: String
    var displayName: String
    var modelId: String
    var author: Author
    var systemPrompt: String
    var isDefault: Bool
    var budgetTokens: Int?
    var reasoningEffort: ReasoningEffort?
    var newUntil: Date?
    
    enum Author: String, Codable {
        case user
        case system
    }
    
    enum ReasoningEffort: String, Codable {
        case low
        case medium
        case high
    }
}

@Model
final class Attachment {
    @Attribute(.unique) var id: String
    var createdAt: Date
    var type: AttachmentType
    var isLoading: Bool
    var originalName: String?
    var path: String
    var isEphemeral: Bool
    
    enum AttachmentType: String, Codable {
        case image
        case pdf
        case text
        case webpage
    }
}
```

### 3.2 Database Migration Strategy

```swift
actor DatabaseMigrator {
    private let legacyDBPath: URL
    private let modelContext: ModelContext
    
    /// Migrate from legacy Chorus SQLite to SwiftData
    func migrateFromChorus() async throws {
        // 1. Check if migration needed
        guard FileManager.default.fileExists(atPath: legacyDBPath.path) else {
            return
        }
        
        // 2. Open legacy SQLite database
        let legacyDB = try SQLiteDatabase(path: legacyDBPath)
        
        // 3. Migrate in order (respecting relationships)
        try await migrateProjects(from: legacyDB)
        try await migrateChats(from: legacyDB)
        try await migrateMessages(from: legacyDB)
        try await migrateAttachments(from: legacyDB)
        try await migrateModelConfigs(from: legacyDB)
        try await migrateToolsetsConfig(from: legacyDB)
        
        // 4. Mark migration complete
        UserDefaults.standard.set(true, forKey: "didMigrateFromChorus")
    }
}
```

---

## 4. AI Provider Layer

### 4.1 Provider Protocol

```swift
/// Protocol for all AI model providers
protocol AIProvider: Actor {
    /// Provider identifier (e.g., "anthropic", "openai")
    var id: String { get }
    
    /// Human-readable name
    var displayName: String { get }
    
    /// Stream a response from the model
    func streamResponse(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (String, [ToolCall]?) async -> Void,
        onError: @escaping (Error) -> Void
    ) async throws
    
    /// Validate API key
    func validateAPIKey(_ key: String) async throws -> Bool
    
    /// List available models
    func listModels() async throws -> [Model]
}

/// Common message format for all providers
enum LLMMessage {
    case user(content: String, attachments: [Attachment])
    case assistant(content: String, model: String?, toolCalls: [ToolCall])
    case toolResults([ToolResult])
}

struct ToolCall: Codable, Identifiable {
    let id: String
    let name: String
    let arguments: [String: Any]
}

struct ToolResult: Codable {
    let id: String
    let content: String
}
```

### 4.2 Anthropic Provider Implementation

```swift
actor AnthropicProvider: AIProvider {
    let id = "anthropic"
    let displayName = "Anthropic"
    
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let keychain: KeychainService
    
    init(keychain: KeychainService) {
        self.keychain = keychain
    }
    
    func streamResponse(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (String, [ToolCall]?) async -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        guard let apiKey = try await keychain.get("anthropic_api_key") else {
            throw ProviderError.missingAPIKey
        }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body = try buildRequestBody(config: config, messages: messages, tools: tools)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Use URLSession for streaming
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ProviderError.requestFailed
        }
        
        var fullText = ""
        var toolCalls: [ToolCall] = []
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            
            guard let data = jsonStr.data(using: .utf8),
                  let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
                continue
            }
            
            switch event.type {
            case "content_block_delta":
                if let text = event.delta?.text {
                    fullText += text
                    onChunk(text)
                }
            case "content_block_start":
                if event.contentBlock?.type == "tool_use" {
                    // Handle tool call start
                }
            case "message_stop":
                await onComplete(fullText, toolCalls.isEmpty ? nil : toolCalls)
            default:
                break
            }
        }
    }
    
    private func buildRequestBody(
        config: ModelConfig,
        messages: [LLMMessage],
        tools: [UserTool]?
    ) throws -> [String: Any] {
        // Convert to Anthropic API format
        var body: [String: Any] = [
            "model": extractModelId(from: config.modelId),
            "max_tokens": 4096,
            "stream": true,
            "messages": messages.map { convertMessage($0) }
        ]
        
        if let systemPrompt = config.systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { convertTool($0) }
        }
        
        if let budget = config.budgetTokens {
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
        }
        
        return body
    }
}
```

### 4.3 Provider Registry

```swift
@MainActor
final class ProviderRegistry: ObservableObject {
    static let shared = ProviderRegistry()
    
    private var providers: [String: any AIProvider] = [:]
    private let keychain = KeychainService.shared
    
    private init() {
        registerBuiltInProviders()
    }
    
    private func registerBuiltInProviders() {
        providers["anthropic"] = AnthropicProvider(keychain: keychain)
        providers["openai"] = OpenAIProvider(keychain: keychain)
        providers["google"] = GoogleProvider(keychain: keychain)
        providers["grok"] = GrokProvider(keychain: keychain)
        providers["openrouter"] = OpenRouterProvider(keychain: keychain)
        providers["perplexity"] = PerplexityProvider(keychain: keychain)
        providers["ollama"] = OllamaProvider()
        providers["lmstudio"] = LMStudioProvider()
    }
    
    func provider(for modelId: String) -> (any AIProvider)? {
        let providerName = modelId.components(separatedBy: "::").first ?? ""
        return providers[providerName]
    }
    
    func streamResponse(for modelConfig: ModelConfig, /* ... */) async throws {
        guard let provider = provider(for: modelConfig.modelId) else {
            throw ProviderError.unknownProvider
        }
        try await provider.streamResponse(/* ... */)
    }
}
```

---

## 5. MCP (Model Context Protocol) Integration

### 5.1 MCP Client

```swift
actor MCPClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var messageId = 0
    private var pendingRequests: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
    
    func connect(command: String, args: [String], env: [String: String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        
        try process.run()
        
        // Start reading responses
        Task {
            await readResponses()
        }
        
        // Initialize connection
        _ = try await sendRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": ["name": "RatuKidulIDE", "version": "1.0.0"]
        ])
        
        try await sendNotification(method: "notifications/initialized", params: [:])
    }
    
    func listTools() async throws -> [MCPTool] {
        let response = try await sendRequest(method: "tools/list", params: [:])
        return try JSONDecoder().decode([MCPTool].self, from: response.result)
    }
    
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let response = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
        // Parse content blocks and return text
        let content = try JSONDecoder().decode([MCPContentBlock].self, from: response.result)
        return content.compactMap { $0.text }.joined(separator: "\n")
    }
    
    private func sendRequest(method: String, params: [String: Any]) async throws -> MCPResponse {
        messageId += 1
        let id = messageId
        
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        
        let data = try JSONSerialization.data(withJSONObject: message)
        stdinPipe?.fileHandleForWriting.write(data)
        stdinPipe?.fileHandleForWriting.write("\n".data(using: .utf8)!)
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }
    
    func disconnect() async {
        process?.terminate()
        process = nil
    }
}
```

### 5.2 Toolset Protocol

```swift
protocol Toolset: Actor {
    var name: String { get }
    var displayName: String { get }
    var description: String? { get }
    var isBuiltIn: Bool { get }
    var status: ToolsetStatus { get }
    
    func start(config: [String: String]) async throws
    func stop() async
    func listTools() async -> [UserTool]
    func executeTool(name: String, arguments: [String: Any]) async throws -> String
}

enum ToolsetStatus: Equatable {
    case stopped
    case starting
    case running
    case error(String)
}

struct UserTool: Identifiable, Codable {
    let id: String
    let toolsetName: String
    let displayName: String
    let description: String?
    let inputSchema: JSONSchema
    
    var namespacedName: String {
        "\(toolsetName)_\(displayName)"
    }
}
```

### 5.3 Built-in Toolsets

```swift
actor FilesToolset: Toolset {
    let name = "files"
    let displayName = "Files"
    let description = "Read and write local files"
    let isBuiltIn = true
    
    private(set) var status: ToolsetStatus = .stopped
    
    func start(config: [String: String]) async throws {
        status = .running
    }
    
    func stop() async {
        status = .stopped
    }
    
    func listTools() async -> [UserTool] {
        [
            UserTool(
                id: "read",
                toolsetName: name,
                displayName: "read",
                description: "Read contents of a file",
                inputSchema: JSONSchema([
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "File path to read"]
                    ],
                    "required": ["path"]
                ])
            ),
            UserTool(
                id: "write",
                toolsetName: name,
                displayName: "write",
                description: "Write contents to a file",
                inputSchema: JSONSchema([
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "File path to write"],
                        "content": ["type": "string", "description": "Content to write"]
                    ],
                    "required": ["path", "content"]
                ])
            )
        ]
    }
    
    func executeTool(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        case "read":
            guard let path = arguments["path"] as? String else {
                throw ToolError.missingArgument("path")
            }
            return try String(contentsOfFile: path, encoding: .utf8)
            
        case "write":
            guard let path = arguments["path"] as? String,
                  let content = arguments["content"] as? String else {
                throw ToolError.missingArgument("path or content")
            }
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return "File written successfully"
            
        default:
            throw ToolError.unknownTool(name)
        }
    }
}
```

---

## 6. UI Layer

### 6.1 Main App Structure

```swift
@main
struct RatuKidulApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, appState.modelContext)
                .environmentObject(appState)
        }
        .commands {
            AppCommands()
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var quickChatPanel: QuickChatPanel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupQuickChatPanel()
        registerGlobalShortcuts()
        NSApp.setActivationPolicy(.regular)
    }
    
    private func setupQuickChatPanel() {
        quickChatPanel = QuickChatPanel()
    }
    
    private func registerGlobalShortcuts() {
        // Register Option+Space for Quick Chat
        GlobalShortcutManager.shared.register(
            shortcut: Shortcut(key: .space, modifiers: .option)
        ) { [weak self] in
            self?.toggleQuickChat()
        }
    }
    
    private func toggleQuickChat() {
        if quickChatPanel?.isVisible == true {
            quickChatPanel?.orderOut(nil)
        } else {
            quickChatPanel?.show()
        }
    }
}
```

### 6.2 Main Content View

```swift
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedProjectId: String?
    @State private var selectedChatId: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedProjectId: $selectedProjectId,
                selectedChatId: $selectedChatId
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            if let chatId = selectedChatId {
                ChatView(chatId: chatId)
            } else {
                EmptyStateView()
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarContent()
        }
    }
}
```

### 6.3 Chat View

```swift
struct ChatView: View {
    let chatId: String
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ChatViewModel
    
    init(chatId: String) {
        self.chatId = chatId
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatId: chatId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messageSets) { messageSet in
                            MessageSetView(messageSet: messageSet)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messageSets.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input area
            ChatInputView(
                text: $viewModel.inputText,
                attachments: $viewModel.attachments,
                selectedModels: $viewModel.selectedModels,
                onSend: viewModel.sendMessage
            )
        }
        .task {
            await viewModel.loadChat()
        }
    }
}

struct MessageBubble: View {
    let message: Message
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Model avatar
            ModelAvatar(modelId: message.modelConfigId)
            
            VStack(alignment: .leading, spacing: 8) {
                // Model name
                Text(message.modelConfig?.displayName ?? "Unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Message content
                MarkdownView(text: message.text)
                    .textSelection(.enabled)
                
                // Tool calls if any
                if let toolCalls = message.decodedToolCalls, !toolCalls.isEmpty {
                    ToolCallsView(toolCalls: toolCalls)
                }
            }
            
            Spacer()
            
            // Hover actions
            if isHovering {
                HStack(spacing: 8) {
                    CopyButton(text: message.text)
                    RegenerateButton(message: message)
                }
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
    }
}
```

### 6.4 Quick Chat Panel

```swift
class QuickChatPanel: NSPanel {
    private var hostingView: NSHostingView<QuickChatView>?
    
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: QuickChatView())
        hostingView.frame = contentRect
        self.contentView = hostingView
        self.hostingView = hostingView
        
        // Apply vibrancy
        let visualEffect = NSVisualEffectView(frame: contentRect)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        self.contentView = visualEffect
        visualEffect.addSubview(hostingView)
    }
    
    func show() {
        // Position at center of screen
        if let screen = NSScreen.main {
            let x = (screen.frame.width - frame.width) / 2
            let y = (screen.frame.height - frame.height) / 2 + 100
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct QuickChatView: View {
    @StateObject private var viewModel = QuickChatViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with model selector
            HStack {
                ModelPickerCompact(selectedModel: $viewModel.selectedModel)
                Spacer()
                Button("Open in Main") {
                    viewModel.openInMainWindow()
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        QuickChatBubble(message: message)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Input
            HStack {
                TextField("Ask anything...", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        viewModel.send()
                    }
                
                Button(action: viewModel.send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.inputText.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
```

---

## 7. Keychain Integration

### 7.1 Keychain Service

```swift
actor KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "sh.ratukidul.ide"
    
    func set(_ value: String, for key: String) throws {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore
        }
    }
    
    func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unableToRetrieve
        }
    }
    
    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }
}
```

---

## 8. Global Shortcuts

### 8.1 Shortcut Manager

```swift
import Carbon

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextId: UInt32 = 1
    
    private init() {
        installEventHandler()
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                let manager = Unmanaged<GlobalShortcutManager>
                    .fromOpaque(userData!)
                    .takeUnretainedValue()
                
                manager.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
    
    struct Shortcut {
        let key: Key
        let modifiers: Modifiers
        
        enum Key: UInt32 {
            case space = 49
            case a = 0
            // ... other keys
        }
        
        struct Modifiers: OptionSet {
            let rawValue: UInt32
            static let option = Modifiers(rawValue: UInt32(optionKey))
            static let command = Modifiers(rawValue: UInt32(cmdKey))
            static let control = Modifiers(rawValue: UInt32(controlKey))
            static let shift = Modifiers(rawValue: UInt32(shiftKey))
        }
    }
    
    func register(shortcut: Shortcut, handler: @escaping () -> Void) {
        let id = nextId
        nextId += 1
        
        var hotKeyID = EventHotKeyID(signature: OSType(1), id: id)
        var hotKeyRef: EventHotKeyRef?
        
        RegisterEventHotKey(
            shortcut.key.rawValue,
            shortcut.modifiers.rawValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        self.hotKeyRef = hotKeyRef
        handlers[id] = handler
    }
}
```

---

## 9. Performance Considerations

### 9.1 Memory Management

```swift
// Use @Observable for lightweight view models (iOS 17+/macOS 14+)
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var isLoading = false
    
    // Lazy loading for large message histories
    func loadMoreMessages() async {
        // Load in batches of 50
    }
}

// Use weak references for delegation
protocol ChatViewModelDelegate: AnyObject {
    func didReceiveMessage(_ message: Message)
}
```

### 9.2 Streaming Optimization

```swift
// Batch UI updates during streaming
actor StreamingBuffer {
    private var buffer = ""
    private var lastFlushTime = Date()
    private let flushInterval: TimeInterval = 0.05 // 50ms
    
    func append(_ text: String) async -> String? {
        buffer += text
        
        let now = Date()
        if now.timeIntervalSince(lastFlushTime) >= flushInterval {
            let flushed = buffer
            buffer = ""
            lastFlushTime = now
            return flushed
        }
        return nil
    }
    
    func flush() -> String {
        let result = buffer
        buffer = ""
        return result
    }
}
```

### 9.3 Caching Strategy

```swift
// In-memory cache for frequently accessed data
actor ModelCache {
    private var cache: [String: ModelConfig] = [:]
    private let maxSize = 100
    
    func get(_ id: String) -> ModelConfig? {
        cache[id]
    }
    
    func set(_ config: ModelConfig) {
        if cache.count >= maxSize {
            // Remove oldest entries
            cache.removeAll()
        }
        cache[config.id] = config
    }
}
```

---

## 10. Testing Strategy

### 10.1 Unit Tests

```swift
@testable import RatuKidulIDE
import XCTest

final class AnthropicProviderTests: XCTestCase {
    var provider: AnthropicProvider!
    var mockKeychain: MockKeychainService!
    
    override func setUp() {
        mockKeychain = MockKeychainService()
        provider = AnthropicProvider(keychain: mockKeychain)
    }
    
    func testValidateAPIKey() async throws {
        mockKeychain.store["anthropic_api_key"] = "sk-valid-key"
        
        // Would need to mock URLSession for actual testing
        let isValid = try await provider.validateAPIKey("sk-valid-key")
        XCTAssertTrue(isValid)
    }
}
```

### 10.2 UI Tests

```swift
import XCTest

final class ChatViewUITests: XCTestCase {
    let app = XCUIApplication()
    
    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }
    
    func testSendMessage() {
        // Create new chat
        app.buttons["New Chat"].click()
        
        // Type message
        let textField = app.textFields["Message input"]
        textField.click()
        textField.typeText("Hello, Claude!")
        
        // Send
        app.buttons["Send"].click()
        
        // Verify message appears
        XCTAssertTrue(app.staticTexts["Hello, Claude!"].waitForExistence(timeout: 5))
    }
}
```

---

## 11. Build & Distribution

### 11.1 Project Configuration

```
// Package.swift
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RatuKidulIDE",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RatuKidulIDE", targets: ["RatuKidulIDE"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.14.0"),
        .package(url: "https://github.com/JohnSundell/Splash", from: "0.16.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "RatuKidulIDE",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Splash", package: "Splash"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
        ),
        .testTarget(
            name: "RatuKidulIDETests",
            dependencies: ["RatuKidulIDE"]
        )
    ]
)
```

### 11.2 Entitlements

```xml
<!-- RatuKidulIDE.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)sh.ratukidul.ide</string>
    </array>
</dict>
</plist>
```

### 11.3 Distribution

| Method | Pros | Cons |
|--------|------|------|
| **Direct DMG** | Full control, instant updates | No auto-update (use Sparkle) |
| **App Store** | Discovery, trust | Review process, sandboxing limits |
| **TestFlight** | Beta testing | Limited to Apple ecosystem |

Recommended: Direct DMG with Sparkle for updates (matching current Chorus approach).

---

## 12. Migration Path

### Phase 1: Core Infrastructure (Weeks 1-4)
- [ ] Xcode project setup
- [ ] SwiftData models
- [ ] Basic navigation shell
- [ ] Single provider (OpenAI)

### Phase 2: Multi-Provider (Weeks 5-8)
- [ ] All 8 providers
- [ ] Streaming implementation
- [ ] Keychain integration
- [ ] Settings UI

### Phase 3: MCP & Tools (Weeks 9-12)
- [ ] MCP client
- [ ] Built-in toolsets
- [ ] Custom toolset support
- [ ] Permission system

### Phase 4: Polish (Weeks 13-16)
- [ ] Quick Chat panel
- [ ] Attachments
- [ ] Data migration from Chorus
- [ ] Performance optimization
- [ ] Beta release

---

## 13. Appendix

### A. Key Dependencies

| Dependency | Purpose | License |
|------------|---------|---------|
| SQLite.swift | Legacy DB migration | MIT |
| Splash | Code syntax highlighting | MIT |
| MarkdownUI | Markdown rendering | MIT |
| Sparkle | Auto-updates | MIT |

### B. API Reference Links

- [Anthropic API](https://docs.anthropic.com/en/api/messages)
- [OpenAI API](https://platform.openai.com/docs/api-reference)
- [Google Gemini API](https://ai.google.dev/api/rest)
- [MCP Specification](https://spec.modelcontextprotocol.io/)

