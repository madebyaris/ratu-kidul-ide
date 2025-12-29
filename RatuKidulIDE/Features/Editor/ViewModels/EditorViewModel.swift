import Foundation
import SwiftUI

/// View model for managing LSP state for a single editor file
@MainActor
@Observable
final class EditorViewModel {
    let filePath: String
    let fileURI: String
    
    // LSP state
    var completions: [CompletionItem] = []
    var diagnostics: [Diagnostic] = []
    var hoverContent: Hover?
    var signatureHelp: SignatureHelp?
    
    // UI state
    var showCompletions = false
    var selectedCompletionIndex = 0
    var hoverPosition: Position?
    
    // Cursor position
    var cursorPosition: Position = Position(line: 0, character: 0)
    
    private let lspManager = LSPManager.shared
    private var documentVersion = 1
    private var languageId: String?
    
    init(filePath: String) {
        self.filePath = filePath
        // Convert file path to file:// URI
        self.fileURI = "file://\(filePath)"
        
        // Detect language synchronously (it's a simple function)
        Task { @MainActor in
            self.languageId = await lspManager.detectLanguage(from: filePath)
        }
    }
    
    /// Set up diagnostics callback (call after initialization)
    func setupDiagnosticsCallback() {
        Task {
            await lspManager.setDiagnosticsCallback { [weak self] uri, diagnostics in
                Task { @MainActor in
                    if uri == self?.fileURI {
                        self?.updateDiagnostics(diagnostics)
                    }
                }
            }
        }
    }
    
    /// Open document in LSP
    func didOpenDocument(content: String) async {
        guard let languageId = languageId else { return }
        
        do {
            try await lspManager.didOpenDocument(
                uri: fileURI,
                languageId: languageId,
                version: documentVersion,
                text: content
            )
        } catch {
            print("Failed to open document in LSP: \(error)")
        }
    }
    
    /// Update document content in LSP
    func didChangeDocument(content: String) async {
        guard languageId != nil else { return }
        
        documentVersion += 1
        
        await lspManager.didChangeDocument(
            uri: fileURI,
            version: documentVersion,
            text: content
        )
    }
    
    /// Close document in LSP
    func didCloseDocument() async {
        guard languageId != nil else { return }
        
        do {
            try await lspManager.didCloseDocument(uri: fileURI)
        } catch {
            print("Failed to close document in LSP: \(error)")
        }
    }
    
    /// Request completion at cursor position
    func requestCompletion() async {
        guard languageId != nil else { return }
        
        do {
            let completionList = try await lspManager.completion(uri: fileURI, position: cursorPosition)
            completions = completionList.items
            showCompletions = !completions.isEmpty
            selectedCompletionIndex = 0
        } catch {
            print("Failed to get completion: \(error)")
            completions = []
            showCompletions = false
        }
    }
    
    /// Request hover at position
    func requestHover(at position: Position) async {
        guard languageId != nil else { return }
        
        do {
            hoverContent = try await lspManager.hover(uri: fileURI, position: position)
            hoverPosition = position
        } catch {
            print("Failed to get hover: \(error)")
            hoverContent = nil
        }
    }
    
    /// Request signature help at cursor position
    func requestSignatureHelp() async {
        guard languageId != nil else { return }
        
        do {
            signatureHelp = try await lspManager.signatureHelp(uri: fileURI, position: cursorPosition)
        } catch {
            print("Failed to get signature help: \(error)")
            signatureHelp = nil
        }
    }
    
    /// Update cursor position
    func updateCursorPosition(line: Int, character: Int) {
        cursorPosition = Position(line: line, character: character)
    }
    
    /// Update diagnostics (called by LSPManager)
    func updateDiagnostics(_ newDiagnostics: [Diagnostic]) {
        diagnostics = newDiagnostics
    }
    
    /// Go to definition
    func goToDefinition() async -> [Location] {
        guard languageId != nil else { return [] }
        
        do {
            return try await lspManager.definition(uri: fileURI, position: cursorPosition)
        } catch {
            print("Failed to go to definition: \(error)")
            return []
        }
    }
    
    /// Find references
    func findReferences() async -> [Location] {
        guard languageId != nil else { return [] }
        
        do {
            return try await lspManager.references(uri: fileURI, position: cursorPosition, includeDeclaration: true)
        } catch {
            print("Failed to find references: \(error)")
            return []
        }
    }
    
    /// Rename symbol
    func rename(to newName: String) async -> WorkspaceEdit? {
        guard languageId != nil else { return nil }
        
        do {
            return try await lspManager.rename(uri: fileURI, position: cursorPosition, newName: newName)
        } catch {
            print("Failed to rename: \(error)")
            return nil
        }
    }
    
    /// Format document
    func formatDocument(tabSize: Int = 4, insertSpaces: Bool = true) async -> [TextEdit] {
        guard languageId != nil else { return [] }
        
        let options = FormattingOptions(tabSize: tabSize, insertSpaces: insertSpaces)
        
        do {
            return try await lspManager.formatting(uri: fileURI, options: options)
        } catch {
            print("Failed to format document: \(error)")
            return []
        }
    }
}
