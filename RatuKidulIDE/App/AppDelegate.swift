import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Shutdown LSP servers gracefully
        Task {
            await LSPManager.shared.shutdown()
            
            // Wait a bit for cleanup
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }
}

