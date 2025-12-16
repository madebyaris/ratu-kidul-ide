import SwiftUI
import SwiftData

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
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        // File menu commands
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                NotificationCenter.default.post(name: .newChat, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            
            Divider()
            
            Button("New File") {
                NotificationCenter.default.post(name: .newFile, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                NotificationCenter.default.post(name: .saveFile, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)
            
            Button("Save All") {
                NotificationCenter.default.post(name: .saveAllFiles, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
        
        // Edit menu - Find commands
        CommandGroup(after: .pasteboard) {
            Divider()
            
            Button("Find...") {
                NotificationCenter.default.post(name: .findInFile, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
            
            Button("Find Next") {
                NotificationCenter.default.post(name: .findNext, object: nil)
            }
            .keyboardShortcut("g", modifiers: .command)
            
            Button("Find Previous") {
                NotificationCenter.default.post(name: .findPrevious, object: nil)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            
            Button("Find and Replace...") {
                NotificationCenter.default.post(name: .findAndReplace, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
        
        // Settings
        CommandGroup(after: .toolbar) {
            Button("Settings...") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        
        // Window menu - close tab
        CommandGroup(after: .windowList) {
            Button("Close Tab") {
                NotificationCenter.default.post(name: .closeTab, object: nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newChat = Notification.Name("newChat")
    static let newFile = Notification.Name("newFile")
    static let saveFile = Notification.Name("saveFile")
    static let saveAllFiles = Notification.Name("saveAllFiles")
    static let findInFile = Notification.Name("findInFile")
    static let findNext = Notification.Name("findNext")
    static let findPrevious = Notification.Name("findPrevious")
    static let findAndReplace = Notification.Name("findAndReplace")
    static let openSettings = Notification.Name("openSettings")
    static let closeTab = Notification.Name("closeTab")
}
