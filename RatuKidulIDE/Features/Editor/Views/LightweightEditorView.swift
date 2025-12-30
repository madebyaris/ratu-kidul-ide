import SwiftUI
import CodeEditorView
import LanguageSupport

/// A lightweight code editor view using TextKit 2 (CodeEditorView)
/// This is significantly lighter than CodeEditSourceEditor for faster compilation
struct LightweightEditorView: View {
    let filePath: String
    @Binding var content: String
    var viewModel: EditorViewModel? = nil
    let onContentChange: (String) -> Void
    
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<LanguageSupport.Message>> = Set()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("editorFontSize") private var editorFontSize: Double = FontSettingsDefaults.editorFontSize
    @AppStorage("showMinimap") private var showMinimap: Bool = false
    @AppStorage("wrapText") private var wrapText: Bool = false
    
    /// Creates a theme with the current font size setting
    private var currentTheme: Theme {
        var theme = colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
        theme.fontSize = CGFloat(editorFontSize)
        return theme
    }
    
    /// Layout configuration for the editor
    private var layoutConfig: CodeEditor.LayoutConfiguration {
        CodeEditor.LayoutConfiguration(
            showMinimap: showMinimap,
            wrapText: wrapText
        )
    }
    
    /// Indentation configuration for the editor
    private var indentationConfig: CodeEditor.IndentationConfiguration {
        .standard
    }
    
    var body: some View {
        CodeEditor(
            text: $content,
            position: $position,
            messages: $messages,
            language: detectLanguage()
        )
        .environment(\.codeEditorTheme, currentTheme)
        .environment(\.codeEditorLayoutConfiguration, layoutConfig)
        .environment(\.codeEditorIndentationConfiguration, indentationConfig)
        .onChange(of: content) { _, newValue in
            onContentChange(newValue)
            
            // Notify LSP of changes
            if let viewModel = viewModel {
                Task {
                    await viewModel.didChangeDocument(content: newValue)
                }
            }
        }
        .onAppear {
            // Open document in LSP
            if let viewModel = viewModel {
                viewModel.setupDiagnosticsCallback()
                Task {
                    await viewModel.didOpenDocument(content: content)
                }
            }
        }
        .onDisappear {
            // Close document in LSP
            if let viewModel = viewModel {
                Task {
                    await viewModel.didCloseDocument()
                }
            }
        }
    }
    
    // TODO: Implement diagnostics display
    // CodeEditorView's Message API needs to be properly understood
    // For now, diagnostics are received by EditorViewModel but not displayed
    
    /// Detect language from file extension
    private func detectLanguage() -> LanguageConfiguration {
        // For now, use Swift configuration for all files
        // TODO: Add proper language detection once we understand CodeEditorView's API better
        return .swift()
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var content = """
        import Foundation
        
        func main() {
            print("Hello, World!")
        }
        
        main()
        """
        
        var body: some View {
            LightweightEditorView(
                filePath: "/test/main.swift",
                content: $content,
                viewModel: nil,
                onContentChange: { _ in }
            )
            .frame(width: 600, height: 400)
        }
    }
    
    return PreviewWrapper()
}
