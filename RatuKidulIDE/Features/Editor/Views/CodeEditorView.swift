import SwiftUI
import AppKit
import CodeEditSourceEditor
import CodeEditLanguages

/// A code editor view wrapping CodeEditSourceEditor (tree-sitter powered)
struct CodeEditorView: View {
    let filePath: String
    @Binding var content: String
    var viewModel: EditorViewModel? = nil
    let onContentChange: (String) -> Void
    
    @State private var language: CodeLanguage = .default
    @State private var editorState = SourceEditorState(
        cursorPositions: [CursorPosition(line: 1, column: 1)]
    )
    @State private var showCompletions = false
    @State private var hoverPosition: CGPoint?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("editorFontSize") private var editorFontSize: Double = FontSettingsDefaults.editorFontSize
    
    /// Editor font based on settings
    private var editorFont: NSFont {
        .monospacedSystemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            SourceEditor(
                $content,
                language: language,
                configuration: SourceEditorConfiguration(
                    appearance: .init(
                        theme: currentTheme,
                        font: editorFont,
                        wrapLines: true
                    ),
                    behavior: .init(
                        indentOption: .spaces(count: 4)
                    ),
                    peripherals: .init(
                        showGutter: true,
                        showMinimap: false
                    )
                ),
                state: $editorState
            )
            .onChange(of: content) { _, newValue in
                onContentChange(newValue)
            }
            .onAppear {
                detectLanguage()
                updateCursorPosition()
            }
            .onChange(of: filePath) { _, _ in
                detectLanguage()
            }
            .onChange(of: colorScheme) { _, _ in
                // Theme will automatically update via currentTheme computed property
            }
            .onChange(of: editorState.cursorPositions) { _, _ in
                updateCursorPosition()
            }
            
            // Completion popup
            if let viewModel = viewModel, viewModel.showCompletions, !viewModel.completions.isEmpty {
                CompletionPopupView(
                    completions: viewModel.completions,
                    selectedIndex: Binding(
                        get: { viewModel.selectedCompletionIndex },
                        set: { viewModel.selectedCompletionIndex = $0 }
                    ),
                    onSelect: { item in
                        viewModel.showCompletions = false
                    }
                )
                .offset(x: 20, y: 40)
            }
            
            // Hover popover
            if let viewModel = viewModel, let hover = viewModel.hoverContent, let position = hoverPosition {
                HoverPopoverView(hover: hover)
                    .position(x: position.x, y: position.y - 20)
            }
        }
    }
    
    /// Update cursor position in view model
    private func updateCursorPosition() {
        guard let viewModel = viewModel,
              let positions = editorState.cursorPositions,
              let cursor = positions.first else {
            return
        }
        
        // Convert to LSP Position (0-based)
        // CursorPosition has .start.line and .start.column (1-indexed)
        let lspPosition = Position(line: cursor.start.line - 1, character: cursor.start.column - 1)
        viewModel.updateCursorPosition(line: lspPosition.line, character: lspPosition.character)
        
        // Request completion on cursor change (debounced in view model)
        Task {
            await viewModel.requestCompletion()
        }
    }
    
    /// Current theme based on color scheme
    private var currentTheme: EditorTheme {
        colorScheme == .dark ? .dark : .light
    }
    
    /// Detect language from file extension
    private func detectLanguage() {
        let ext = (filePath as NSString).pathExtension.lowercased()
        language = languageForExtension(ext)
    }
    
    /// Map file extension to CodeLanguage
    private func languageForExtension(_ ext: String) -> CodeLanguage {
        switch ext {
        case "swift":
            return .swift
        case "js", "cjs", "mjs":
            return .javascript
        case "jsx":
            return .jsx
        case "ts", "cts", "mts":
            return .typescript
        case "tsx":
            return .tsx
        case "py":
            return .python
        case "rs":
            return .rust
        case "go":
            return .go
        case "java", "jav":
            return .java
        case "kt", "kts":
            return .kotlin
        case "c":
            return .c
        case "cpp", "cc", "cxx", "c++", "hpp":
            return .cpp
        case "h":
            return .c // Header files default to C
        case "cs":
            return .cSharp
        case "rb":
            return .ruby
        case "php":
            return .php
        case "html", "htm", "shtml":
            return .html
        case "css":
            return .css
        case "json":
            return .json
        case "yml", "yaml":
            return .yaml
        case "md", "mkd", "mkdn", "mdwn", "mdown", "markdown":
            return .markdown
        case "sh", "bash":
            return .bash
        case "sql":
            return .sql
        case "dockerfile":
            return .dockerfile
        case "toml":
            return .toml
        case "lua":
            return .lua
        case "perl", "pl", "pm":
            return .perl
        case "dart":
            return .dart
        case "ex", "exs":
            return .elixir
        case "zig":
            return .zig
        case "hs":
            return .haskell
        case "ml":
            return .ocaml
        case "mli":
            return .ocamlInterface
        case "m":
            return .objc
        case "scala", "sc":
            return .scala
        case "jl":
            return .julia
        case "v":
            return .verilog
        case "agda":
            return .agda
        case "mod":
            return .goMod
        default:
            return .default
        }
    }
}

// MARK: - EditorTheme Extensions

extension EditorTheme {
    /// Light theme matching Xcode's default light appearance
    static var light: EditorTheme {
        EditorTheme(
            text: Attribute(color: NSColor(hex: "000000")),
            insertionPoint: NSColor(hex: "000000"),
            invisibles: Attribute(color: NSColor(hex: "D6D6D6")),
            background: NSColor(hex: "FFFFFF"),
            lineHighlight: NSColor(hex: "ECF5FF"),
            selection: NSColor(hex: "B2D7FF"),
            keywords: Attribute(color: NSColor(hex: "9B2393"), bold: true),
            commands: Attribute(color: NSColor(hex: "326D74")),
            types: Attribute(color: NSColor(hex: "0B4F79")),
            attributes: Attribute(color: NSColor(hex: "815F03")),
            variables: Attribute(color: NSColor(hex: "0F68A0")),
            values: Attribute(color: NSColor(hex: "6C36A9")),
            numbers: Attribute(color: NSColor(hex: "1C00CF")),
            strings: Attribute(color: NSColor(hex: "C41A16")),
            characters: Attribute(color: NSColor(hex: "1C00CF")),
            comments: Attribute(color: NSColor(hex: "267507"))
        )
    }
    
    /// Dark theme matching Xcode's default dark appearance
    static var dark: EditorTheme {
        EditorTheme(
            text: Attribute(color: NSColor(hex: "FFFFFF")),
            insertionPoint: NSColor(hex: "007AFF"),
            invisibles: Attribute(color: NSColor(hex: "53606E")),
            background: NSColor(hex: "292A30"),
            lineHighlight: NSColor(hex: "2F3239"),
            selection: NSColor(hex: "646F83"),
            keywords: Attribute(color: NSColor(hex: "FF7AB2"), bold: true),
            commands: Attribute(color: NSColor(hex: "78C2B3")),
            types: Attribute(color: NSColor(hex: "6BDFFF")),
            attributes: Attribute(color: NSColor(hex: "CC9768")),
            variables: Attribute(color: NSColor(hex: "4EB0CC")),
            values: Attribute(color: NSColor(hex: "B281EB")),
            numbers: Attribute(color: NSColor(hex: "D9C97C")),
            strings: Attribute(color: NSColor(hex: "FF8170")),
            characters: Attribute(color: NSColor(hex: "D9C97C")),
            comments: Attribute(color: NSColor(hex: "7F8C98"))
        )
    }
}

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
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
            CodeEditorView(
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
