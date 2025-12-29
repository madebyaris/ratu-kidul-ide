# LSP Integration Guide

## Current Status

✅ **All LSP infrastructure code has been created and is ready to use!**

The app currently runs but **LSP features are disabled** because the files haven't been added to the Xcode project target yet.

## What's Been Created

### Core LSP Infrastructure (11 files)
Located in `RatuKidulIDE/Core/LSP/`:

1. **LSPTypes.swift** - Swift types matching LSP specification
2. **LSPError.swift** - Custom error types for LSP operations
3. **LSPLogger.swift** - Structured logging for debugging
4. **JSONRPCTransport.swift** - JSON-RPC communication layer
5. **LanguageServerConfig.swift** - Configuration for different language servers
6. **DocumentVersionManager.swift** - Tracks document versions and generates incremental edits
7. **LSPSession.swift** - Manages single language server connection
8. **LSPDebouncer.swift** - Debouncing/throttling for performance
9. **LSPCache.swift** - LRU cache for LSP responses
10. **LSPServerPool.swift** - Manages language server processes
11. **LSPManager.swift** - Central coordinator for all LSP operations

### Editor Integration (4 files)

**ViewModel:**
- `RatuKidulIDE/Features/Editor/ViewModels/EditorViewModel.swift`

**UI Components:**
- `RatuKidulIDE/Features/Editor/Views/CompletionPopupView.swift`
- `RatuKidulIDE/Features/Editor/Views/DiagnosticsGutterView.swift`
- `RatuKidulIDE/Features/Editor/Views/HoverPopoverView.swift`

## LSP Features Implemented

Once enabled, you'll get:

✨ **Code Completion** - Intelligent autocomplete suggestions
🔍 **Hover Information** - Documentation on hover
⚠️ **Diagnostics** - Real-time error and warning indicators
🎯 **Go to Definition** - Jump to symbol definitions
📖 **Find References** - Find all usages of a symbol
✏️ **Rename** - Rename symbols across files
💡 **Code Actions** - Quick fixes and refactorings
🎨 **Document Formatting** - Auto-format code

## Performance Optimizations

The implementation includes:

- ⚡ **Debouncing** - Prevents overwhelming the server
- 📦 **Incremental Sync** - Only sends changed text
- 💾 **Response Caching** - LRU cache for fast repeated requests
- 🚀 **Lazy Startup** - Servers start only when needed
- 🔄 **Request Cancellation** - Cancels outdated requests
- 🎯 **Server Pooling** - Efficient resource management

## Supported Languages

Pre-configured for:

- Swift (sourcekit-lsp)
- TypeScript/JavaScript (typescript-language-server)
- Python (pyright)
- Go (gopls)
- Rust (rust-analyzer)
- C/C++ (clangd)
- HTML (vscode-html-language-server)
- CSS (vscode-css-language-server)

## How to Enable LSP Integration

### Step 1: Add Files to Xcode Project

1. **Open** `RatuKidulIDE.xcodeproj` in Xcode

2. **Add LSP Core Files:**
   - Right-click on `RatuKidulIDE` folder in Project Navigator
   - Select "Add Files to 'RatuKidulIDE'..."
   - Navigate to `RatuKidulIDE/Core/LSP/`
   - Select **ALL** `.swift` files (Cmd+A)
   - **UNCHECK** "Copy items if needed" (files are already in place)
   - **CHECK** the "RatuKidulIDE" target
   - Click "Add"

3. **Add Editor Integration Files:**
   - Repeat the process for these files:
     - `RatuKidulIDE/Features/Editor/ViewModels/EditorViewModel.swift`
     - `RatuKidulIDE/Features/Editor/Views/CompletionPopupView.swift`
     - `RatuKidulIDE/Features/Editor/Views/DiagnosticsGutterView.swift`
     - `RatuKidulIDE/Features/Editor/Views/HoverPopoverView.swift`

4. **Verify** all files appear in the Project Navigator with the target checkbox selected

### Step 2: Uncomment LSP Integration Code

Once files are added to the target, uncomment the LSP code in these files:

#### 1. `AppState.swift` (lines 72-77, 81-98, 101-105)

Find and uncomment:
```swift
// Initialize LSP Manager
Task {
    await updateLSPProjectRoot()
}
```

And:
```swift
private func updateLSPProjectRoot() {
    Task {
        if let projectId = selectedProjectId {
            // ... full implementation
        }
    }
}

func shutdown() {
    Task {
        await LSPManager.shared.shutdown()
    }
}
```

#### 2. `AppDelegate.swift` (lines 12-19)

Find and uncomment:
```swift
func applicationWillTerminate(_ notification: Notification) {
    Task {
        await LSPManager.shared.shutdown()
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}
```

#### 3. `EditorContentView.swift` (lines 38-91)

Replace the simplified `FileEditorWrapper` with the full LSP-integrated version:

```swift
struct FileEditorWrapper: View {
    let filePath: String
    @Bindable var tabManager: EditorTabManager
    @State private var viewModel: EditorViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                let contentBinding = Binding<String>(
                    get: { tabManager.fileContents[filePath] ?? "" },
                    set: { newValue in
                        tabManager.updateFileContent(path: filePath, content: newValue)
                        Task {
                            await viewModel.didChangeDocument(content: newValue)
                        }
                    }
                )
                
                CodeEditorView(
                    filePath: filePath,
                    content: contentBinding,
                    viewModel: viewModel,
                    onContentChange: { _ in }
                )
            } else {
                ProgressView()
            }
        }
        .task {
            let vm = EditorViewModel(filePath: filePath)
            self.viewModel = vm
            vm.setupDiagnosticsCallback()
            if let content = tabManager.fileContents[filePath] {
                await vm.didOpenDocument(content: content)
            }
        }
        .onDisappear {
            if let vm = viewModel {
                Task {
                    await vm.didCloseDocument()
                }
            }
        }
    }
}
```

#### 4. `CodeEditorView.swift`

Uncomment:
- Line 13: `var viewModel: EditorViewModel? = nil`
- Lines 63-87: Completion popup and hover popover
- Lines 92-106: `updateCursorPosition()` method
- Line 55: `updateCursorPosition()` call

### Step 3: Build and Run

1. Build the project: **Cmd+B**
2. Fix any remaining errors (should be none if all files are added)
3. Run the app: **Cmd+R**

## Testing LSP Features

### 1. Test Code Completion

1. Open a Swift file
2. Start typing a variable or function name
3. You should see completion suggestions appear

### 2. Test Diagnostics

1. Open a Swift file
2. Introduce a syntax error (e.g., `let x = `)
3. You should see error indicators in the gutter

### 3. Test Hover

1. Hover over a function or variable
2. You should see documentation in a popover

### 4. Test Go to Definition

1. Cmd+Click on a symbol
2. Should jump to its definition

## Troubleshooting

### Language Server Not Found

If you get "Language server not found" errors:

1. **For Swift:** Ensure Xcode Command Line Tools are installed:
   ```bash
   xcode-select --install
   ```

2. **For TypeScript:** Install the language server:
   ```bash
   npm install -g typescript-language-server typescript
   ```

3. **For Python:** Install pyright:
   ```bash
   npm install -g pyright
   ```

### No Completions Appearing

1. Check the console for LSP errors
2. Verify the language server is installed
3. Check that the file extension is recognized
4. Ensure the project root is set correctly

### Performance Issues

1. Check LSP logs in the console
2. Adjust debounce delays in `LSPDebouncer.swift`
3. Reduce cache size in `LSPCache.swift`
4. Limit concurrent servers in `LSPServerPool.swift`

## Architecture Overview

```
┌─────────────────────────────────────────┐
│         CodeEditorView (UI)             │
│  - Displays code                        │
│  - Shows completions, diagnostics       │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│       EditorViewModel                   │
│  - Manages LSP state for one file       │
│  - Handles UI updates                   │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│         LSPManager (Actor)              │
│  - Coordinates all LSP operations       │
│  - Routes requests to correct server    │
└──────────────┬──────────────────────────┘
               │
    ┌──────────┼──────────┐
    │          │          │
┌───▼───┐  ┌──▼───┐  ┌──▼───┐
│Session│  │Cache │  │Pool  │
│       │  │      │  │      │
└───┬───┘  └──────┘  └──────┘
    │
┌───▼────────────────────────────────────┐
│   Language Server Process              │
│   (sourcekit-lsp, typescript-ls, etc.) │
└────────────────────────────────────────┘
```

## Next Steps

After enabling LSP:

1. **Add Settings UI** - Configure language servers from Settings
2. **Add More Languages** - Extend `LanguageServerConfig`
3. **Improve UI** - Enhance completion popup styling
4. **Add Tests** - Write unit tests for LSP components
5. **Performance Tuning** - Monitor and optimize based on usage

## Resources

- [LSP Specification](https://microsoft.github.io/language-server-protocol/)
- [sourcekit-lsp Documentation](https://github.com/apple/sourcekit-lsp)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)

---

**Questions?** Check the implementation files for detailed comments and documentation.
