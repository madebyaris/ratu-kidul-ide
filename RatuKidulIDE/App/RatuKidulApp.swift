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
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                // TODO: Implement new chat
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        
        CommandGroup(after: .toolbar) {
            Button("Settings...") {
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

