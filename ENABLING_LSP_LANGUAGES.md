# Enabling Language Server Support

## How It Works

The IDE **automatically activates the correct LSP for each file type** when you open a tab. No manual switching needed!

- Open a `.swift` file → Swift LSP activates
- Open a `.php` file → PHP LSP activates (if installed & enabled)
- Open a `.ts` file → TypeScript LSP activates (if installed & enabled)
- etc.

## Currently Supported Languages

| Language | Extension | LSP Server | Status |
|----------|-----------|------------|--------|
| **Swift** | `.swift` | sourcekit-lsp | ✅ **Enabled by default** |
| **PHP** | `.php` | intelephense | ⚠️ Disabled (install required) |
| **TypeScript** | `.ts`, `.tsx` | typescript-language-server | ⚠️ Disabled (install required) |
| **JavaScript** | `.js`, `.jsx` | typescript-language-server | ⚠️ Disabled (install required) |
| **Python** | `.py` | pyright | ⚠️ Disabled (install required) |
| **Go** | `.go` | gopls | ⚠️ Disabled (install required) |
| **Rust** | `.rs` | rust-analyzer | ⚠️ Disabled (install required) |
| **C/C++** | `.c`, `.cpp`, `.h` | clangd | ⚠️ Disabled (install required) |
| **HTML** | `.html`, `.htm` | vscode-html-languageserver | ⚠️ Disabled (install required) |
| **CSS** | `.css`, `.scss` | vscode-css-languageserver | ⚠️ Disabled (install required) |

## Enabling PHP Language Server

### Step 1: Install Intelephense

```bash
# Using npm (requires Node.js)
npm install -g intelephense

# Verify installation
which intelephense
# Should output: /usr/local/bin/intelephense (or similar)
```

### Step 2: Enable in IDE

**Option A: Via Configuration File** (Recommended for now)

Edit: `RatuKidulIDE/Core/LSP/LanguageServerConfig.swift`

Find the `php()` function and change:
```swift
isEnabled: false,  // Change this to true
```

To:
```swift
isEnabled: true,   // Now enabled!
```

**Option B: Via Settings UI** (Coming soon)

Future versions will have a Settings UI to enable/disable language servers without code changes.

### Step 3: Rebuild and Run

```bash
# Clean build
⌘ + Shift + K

# Build and run
⌘ + R
```

### Step 4: Test

1. Open a `.php` file
2. Start typing PHP code
3. You should see autocomplete suggestions!

## Enabling Other Languages

### TypeScript/JavaScript

```bash
# Install
npm install -g typescript typescript-language-server

# Enable in LanguageServerConfig.swift
# Find typescript() function, set isEnabled: true
```

### Python

```bash
# Install
npm install -g pyright

# Enable in LanguageServerConfig.swift
# Find python() function, set isEnabled: true
```

### Go

```bash
# Install (requires Go to be installed)
go install golang.org/x/tools/gopls@latest

# Enable in LanguageServerConfig.swift
# Find go() function, set isEnabled: true
```

### Rust

```bash
# Install (via rustup)
rustup component add rust-analyzer

# Enable in LanguageServerConfig.swift
# Find rust() function, set isEnabled: true
```

### C/C++

```bash
# macOS (via Homebrew)
brew install llvm

# Linux
sudo apt install clangd

# Enable in LanguageServerConfig.swift
# Find cpp() function, set isEnabled: true
```

## Verification

After enabling a language server, check the console when opening a file:

```
Server [php]: Starting
  /usr/local/bin/intelephense
Server [php]: Process launched (PID: xxxxx)
📤 Sending JSON-RPC: {"jsonrpc":"2.0","id":1,"method":"initialize",...}
✅ Successfully wrote XXXX bytes to stdin
Server [php]: Initialized
```

## Troubleshooting

### "Server not found" Error

```
Server [php]: Launch failed
  The file "intelephense" doesn't exist.
```

**Solution**: 
1. Check installation: `which intelephense`
2. Make sure the path is correct
3. Add to PATH if needed: `export PATH="/usr/local/bin:$PATH"`

### Server Crashes

Check console for stderr output from the language server. Common issues:
- Wrong version
- Missing dependencies
- Configuration errors

### No Autocomplete

1. **Check console** for "Initialized" message
2. **Wait a moment** - first indexing can take time
3. **Try typing more** - some servers need context
4. **Check file extension** - must match exactly (`.php`, not `.PHP`)

## Performance Tips

**Don't enable all language servers at once!**

- Only enable the ones you actively use
- Each LSP consumes memory and CPU
- Start with 2-3 languages max
- Add more as needed

## Coming Soon

- ✨ **Settings UI** - Enable/disable servers without code changes
- ✨ **Auto-install** - One-click installation of language servers
- ✨ **Status indicator** - See which LSP is active for current file
- ✨ **LSP logs viewer** - Debug LSP issues in-app

---

**Last Updated**: December 30, 2025  
**Status**: ✅ Multi-language LSP support ready, install servers as needed
