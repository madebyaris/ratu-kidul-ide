import Foundation

/// Configuration for a language server
struct LanguageServerConfig: Codable, Equatable {
    /// Language identifier (e.g., "swift", "typescript")
    var languageId: String
    
    /// Display name for the language
    var displayName: String
    
    /// Path to the language server executable
    var executablePath: String
    
    /// Command-line arguments for the server
    var arguments: [String]
    
    /// Environment variables to set
    var environment: [String: String]
    
    /// Initialization options to send to the server
    var initializationOptions: [String: AnyCodable]?
    
    /// Whether this server is enabled
    var isEnabled: Bool
    
    /// Whether to auto-detect the server path
    var autoDetect: Bool
    
    init(
        languageId: String,
        displayName: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        initializationOptions: [String: AnyCodable]? = nil,
        isEnabled: Bool = true,
        autoDetect: Bool = true
    ) {
        self.languageId = languageId
        self.displayName = displayName
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.initializationOptions = initializationOptions
        self.isEnabled = isEnabled
        self.autoDetect = autoDetect
    }
    
    /// Create a default configuration for Swift (sourcekit-lsp)
    static func swift() -> LanguageServerConfig {
        // Try to find sourcekit-lsp in common locations
        let possiblePaths = [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp",
            "/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/sourcekit-lsp",
            "/usr/local/bin/sourcekit-lsp",
            "/usr/bin/sourcekit-lsp",
            "/Library/Developer/CommandLineTools/usr/bin/sourcekit-lsp"
        ]
        
        var executablePath = "sourcekit-lsp"
        
        // Check if any path exists
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                executablePath = path
                print("✅ Found sourcekit-lsp at: \(path)")
                break
            }
        }
        
        if executablePath == "sourcekit-lsp" {
            print("⚠️ Using PATH-based sourcekit-lsp (not found in standard locations)")
        }
        
        return LanguageServerConfig(
            languageId: "swift",
            displayName: "Swift",
            executablePath: executablePath,
            arguments: [],
            environment: [:],
            initializationOptions: nil // sourcekit-lsp doesn't need initialization options
        )
    }
    
    /// Create a default configuration for TypeScript/JavaScript
    static func typescript() -> LanguageServerConfig {
        return LanguageServerConfig(
            languageId: "typescript",
            displayName: "TypeScript",
            executablePath: "typescript-language-server",
            arguments: ["--stdio"],
            environment: [:],
            initializationOptions: [
                "hostInfo": AnyCodable("ratu-kidul-ide"),
                "maxTsServerMemory": AnyCodable(4096)
            ],
            isEnabled: false, // Disabled by default - user must install and enable
            autoDetect: true
        )
    }
    
    /// Create a default configuration for Python (pyright)
    static func python() -> LanguageServerConfig {
        return LanguageServerConfig(
            languageId: "python",
            displayName: "Python",
            executablePath: "pyright-langserver",
            arguments: ["--stdio"],
            environment: [:],
            initializationOptions: [
                "python": AnyCodable([
                    "analysis": AnyCodable([
                        "typeCheckingMode": AnyCodable("basic")
                    ])
                ])
            ],
            isEnabled: false, // Disabled by default - user must install and enable
            autoDetect: true
        )
    }
    
    /// Create a default configuration for Go (gopls)
    static func go() -> LanguageServerConfig {
        return LanguageServerConfig(
            languageId: "go",
            displayName: "Go",
            executablePath: "gopls",
            arguments: [],
            environment: [:],
            initializationOptions: [
                "gopls": AnyCodable([
                    "build.completeUnimported": AnyCodable(true),
                    "ui.completion.usePlaceholders": AnyCodable(true)
                ])
            ],
            isEnabled: false, // Disabled by default - user must install and enable
            autoDetect: true
        )
    }
    
    /// Create a default configuration for Rust (rust-analyzer)
    static func rust() -> LanguageServerConfig {
        return LanguageServerConfig(
            languageId: "rust",
            displayName: "Rust",
            executablePath: "rust-analyzer",
            arguments: [],
            environment: [:],
            initializationOptions: [
                "rust-analyzer": AnyCodable([
                    "checkOnSave": AnyCodable(true),
                    "cargo": AnyCodable([
                        "allFeatures": AnyCodable(true)
                    ])
                ])
            ],
            isEnabled: false, // Disabled by default - user must install and enable
            autoDetect: true
        )
    }
    
    /// Create a default configuration for C/C++ (clangd)
    static func cpp() -> LanguageServerConfig {
        return LanguageServerConfig(
            languageId: "cpp",
            displayName: "C/C++",
            executablePath: "clangd",
            arguments: [],
            environment: [:],
            initializationOptions: [
                "clangd": AnyCodable([
                    "completion": AnyCodable([
                        "allScopes": AnyCodable(true)
                    ])
                ])
            ],
            isEnabled: false, // Disabled by default - user must install and enable
            autoDetect: true
        )
    }
    
    /// Create a default configuration for HTML
    static func html() -> LanguageServerConfig {
        return LanguageServerConfig(
            languageId: "html",
            displayName: "HTML",
            executablePath: "vscode-html-languageserver",
            arguments: ["--stdio"],
            environment: [:],
            isEnabled: false, // Disabled by default - user must install and enable
            autoDetect: true
        )
    }
    
    /// Create a default configuration for CSS
    static func css() -> LanguageServerConfig {
        return LanguageServerConfig(
            languageId: "css",
            displayName: "CSS",
            executablePath: "vscode-css-languageserver",
            arguments: ["--stdio"],
            environment: [:],
            isEnabled: false, // Disabled by default - user must install and enable
            autoDetect: true
        )
    }
    
    /// Create a default configuration for PHP (Intelephense)
    static func php() -> LanguageServerConfig {
        return LanguageServerConfig(
            languageId: "php",
            displayName: "PHP",
            executablePath: "intelephense",
            arguments: ["--stdio"],
            environment: [:],
            initializationOptions: [
                "licenceKey": AnyCodable(""), // Optional: add license key if you have one
                "storagePath": AnyCodable("/tmp/intelephense")
            ],
            isEnabled: false, // Disabled by default - user must install and enable
            autoDetect: true
        )
    }
    
    /// Detect if the server executable exists
    func detectExecutable() -> String? {
        // If it's an absolute path, check if it exists
        if executablePath.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: executablePath) {
                return executablePath
            }
            return nil
        }
        
        // Otherwise, check PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executablePath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Ignore errors
        }
        
        return nil
    }
}
