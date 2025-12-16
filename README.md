# Ratu Kidul IDE

A native macOS AI-powered development environment built with SwiftUI.

## Features

- **Multi-Model Chat**: Query multiple AI models simultaneously
- **Bring Your Own Key (BYOK)**: Use your own API keys stored securely in macOS Keychain
- **Native Performance**: Built with SwiftUI for optimal macOS performance
- **Git-Optional**: Works with or without git repositories

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Building

### Option 1: Using XcodeGen (Recommended)

1. Install XcodeGen if you haven't already:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   cd ratu-kidul-ide
   xcodegen generate
   ```

3. Open the generated project:
   ```bash
   open RatuKidulIDE.xcodeproj
   ```

### Option 2: Using Swift Package Manager

1. Open Package.swift in Xcode:
   ```bash
   cd ratu-kidul-ide
   open Package.swift
   ```

2. Xcode will create a temporary project. For a permanent project, use Option 1.

### Option 3: Manual Xcode Project

1. Create a new macOS App project in Xcode
2. Add all files from the `RatuKidulIDE` folder
3. Configure the bundle identifier to `sh.ratukidul.ide`
4. Set deployment target to macOS 14.0
5. Add the entitlements file to the project

## Project Structure

```
RatuKidulIDE/
├── App/              # App entry point and lifecycle
├── Features/         # Feature modules (Chat, Settings, etc.)
├── Core/            # Core services and providers
├── Data/            # SwiftData models
├── Shared/          # Shared components and utilities
└── Resources/       # Assets and configuration files
```

## Configuration

1. Launch the app
2. Go to Settings → API Keys
3. Enter your API keys for OpenAI, Anthropic, or Google
4. Keys are stored securely in macOS Keychain

## Development Status

This is Phase 1 implementation with:
- ✅ SwiftData models
- ✅ OpenAI provider with streaming
- ✅ Basic chat UI
- ✅ Keychain integration
- ✅ Settings UI

Coming in future phases:
- Additional AI providers (Anthropic, Google, etc.)
- MCP tool integration
- Quick Chat panel
- Attachments support
- Project management

## License

MIT

