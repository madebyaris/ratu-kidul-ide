import Foundation
import SwiftUI

/// Manages the state of editor tabs
@Observable
final class EditorTabManager {
    /// All open tabs (chat tab is always first)
    var tabs: [EditorTab] = [.chatTab()]
    
    /// ID of the currently active tab
    var activeTabId: String = "chat"
    
    /// Content cache for open files (path -> content)
    var fileContents: [String: String] = [:]
    
    /// Original content when file was opened (for detecting modifications)
    private var originalContents: [String: String] = [:]
    
    /// Whether the search panel is visible
    var isSearchVisible: Bool = false
    
    /// Current search query
    var searchQuery: String = ""
    
    /// Currently active tab
    var activeTab: EditorTab? {
        tabs.first { $0.id == activeTabId }
    }
    
    /// Check if a file is already open
    func isFileOpen(path: String) -> Bool {
        tabs.contains { $0.id == path }
    }
    
    /// Open a file in a new tab (or switch to existing tab)
    func openFile(path: String, name: String) {
        // If file is already open, just switch to it
        if isFileOpen(path: path) {
            activeTabId = path
            return
        }
        
        // Create new tab and add after chat tab
        let newTab = EditorTab.fileTab(path: path, name: name)
        tabs.append(newTab)
        activeTabId = path
        
        // Load file content
        loadFileContent(path: path)
    }
    
    /// Close a tab by ID
    func closeTab(id: String) {
        guard let tab = tabs.first(where: { $0.id == id }), tab.canClose else {
            return
        }
        
        // Remove from tabs
        tabs.removeAll { $0.id == id }
        
        // Clean up cached content
        fileContents.removeValue(forKey: id)
        originalContents.removeValue(forKey: id)
        
        // If closing active tab, switch to another tab
        if activeTabId == id {
            // Try to select the previous tab, or chat tab as fallback
            if let lastFileTab = tabs.last(where: { $0.type.isChat == false }) {
                activeTabId = lastFileTab.id
            } else {
                activeTabId = "chat"
            }
        }
    }
    
    /// Set the active tab
    func setActiveTab(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }
    
    /// Update file content (called when user edits)
    func updateFileContent(path: String, content: String) {
        fileContents[path] = content
        
        // Check if modified
        let isModified = originalContents[path] != content
        if let index = tabs.firstIndex(where: { $0.id == path }) {
            tabs[index].isModified = isModified
        }
    }
    
    /// Save the currently active file
    func saveActiveFile() throws {
        guard let tab = activeTab,
              case .file(let path, _) = tab.type,
              let content = fileContents[path] else {
            return
        }
        
        try saveFile(path: path, content: content)
    }
    
    /// Save a specific file
    func saveFile(path: String, content: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        
        // Update original content and clear modified flag
        originalContents[path] = content
        if let index = tabs.firstIndex(where: { $0.id == path }) {
            tabs[index].isModified = false
        }
    }
    
    /// Load file content from disk
    private func loadFileContent(path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            fileContents[path] = content
            originalContents[path] = content
        } catch {
            print("Failed to load file: \(error)")
            fileContents[path] = "// Error loading file: \(error.localizedDescription)"
            originalContents[path] = ""
        }
    }
    
    /// Check if any tabs have unsaved changes
    var hasUnsavedChanges: Bool {
        tabs.contains { $0.isModified }
    }
    
    /// Get all tabs with unsaved changes
    var unsavedTabs: [EditorTab] {
        tabs.filter { $0.isModified }
    }
    
    /// Close all file tabs (keeps chat tab)
    func closeAllFileTabs() {
        tabs.removeAll { $0.canClose }
        fileContents.removeAll()
        originalContents.removeAll()
        activeTabId = "chat"
    }
    
    /// Close other tabs (keeps active tab and chat tab)
    func closeOtherTabs() {
        let currentId = activeTabId
        tabs.removeAll { $0.id != currentId && $0.canClose }
        
        // Clean up cached content for closed tabs
        let openPaths = Set(tabs.compactMap { $0.type.filePath })
        fileContents = fileContents.filter { openPaths.contains($0.key) }
        originalContents = originalContents.filter { openPaths.contains($0.key) }
    }
}

