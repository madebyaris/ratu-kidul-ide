import Foundation

/// Manages a single connection to a language server
actor LSPSession {
    private let config: LanguageServerConfig
    private let projectRoot: String?
    private var transport: JSONRPCTransport?
    private var process: Process?
    private var isInitialized = false
    private var serverCapabilities: ServerCapabilities?
    private let documentManager = DocumentVersionManager()
    private let logger = LSPLogger.shared
    
    /// Callback for diagnostics updates
    private var onDiagnostics: (@Sendable (String, [Diagnostic]) -> Void)?
    
    /// Callback for other notifications
    private var onNotification: (@Sendable (String, AnyCodable?) -> Void)?
    
    init(config: LanguageServerConfig, projectRoot: String?) {
        self.config = config
        self.projectRoot = projectRoot
    }
    
    /// Set callback for diagnostics updates
    func setDiagnosticsCallback(_ callback: @escaping @Sendable (String, [Diagnostic]) -> Void) {
        onDiagnostics = callback
    }
    
    /// Set callback for notification updates
    func setNotificationCallback(_ callback: @escaping @Sendable (String, AnyCodable?) -> Void) {
        onNotification = callback
    }
    
    /// Start the language server
    func start() async throws {
        guard process == nil else {
            throw LSPError.initializationFailed("Server already started")
        }
        
        // Detect executable if needed
        let executablePath: String
        if config.autoDetect, let detected = config.detectExecutable() {
            executablePath = detected
        } else {
            executablePath = config.executablePath
        }
        
        // Check if executable exists
        if executablePath.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: executablePath) else {
                throw LSPError.serverNotFound(config.languageId)
            }
        }
        
        await logger.logServerLifecycle(language: config.languageId, event: "Starting", details: executablePath)
        
        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = config.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(config.environment) { _, new in new }
        
        // Create transport
        let transport = JSONRPCTransport()
        await transport.initialize(process: process)
        
        // Set notification handler
        await transport.setNotificationHandler { [weak self] method, params in
            Task { @MainActor in
                await self?.handleNotification(method: method, params: params)
            }
        }
        
        self.process = process
        self.transport = transport
        
        // Launch process
        do {
            try process.run()
        } catch {
            await logger.logServerLifecycle(language: config.languageId, event: "Launch failed", details: error.localizedDescription)
            throw LSPError.processLaunchFailed(executablePath, error.localizedDescription)
        }
        
        // Initialize LSP connection
        try await initialize()
    }
    
    /// Initialize the LSP connection
    private func initialize() async throws {
        guard let transport = transport else {
            throw LSPError.connectionLost
        }
        
        let rootURI: String?
        if let projectRoot = projectRoot {
            rootURI = "file://\(projectRoot)"
        } else {
            rootURI = nil
        }
        
        let initializeParams: [String: AnyCodable] = [
            "processId": AnyCodable(ProcessInfo.processInfo.processIdentifier),
            "clientInfo": AnyCodable([
                "name": AnyCodable("Ratu Kidul IDE"),
                "version": AnyCodable("1.0.0")
            ]),
            "locale": AnyCodable("en-US"),
            "rootPath": AnyCodable(projectRoot),
            "rootUri": AnyCodable(rootURI),
            "capabilities": AnyCodable([
                "workspace": AnyCodable([
                    "applyEdit": AnyCodable(true),
                    "workspaceEdit": AnyCodable([
                        "documentChanges": AnyCodable(true)
                    ]),
                    "didChangeConfiguration": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "didChangeWatchedFiles": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "symbol": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "executeCommand": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ])
                ]),
                "textDocument": AnyCodable([
                    "synchronization": AnyCodable([
                        "dynamicRegistration": AnyCodable(true),
                        "willSave": AnyCodable(true),
                        "willSaveWaitUntil": AnyCodable(true),
                        "didSave": AnyCodable(true)
                    ]),
                    "completion": AnyCodable([
                        "dynamicRegistration": AnyCodable(true),
                        "completionItem": AnyCodable([
                            "snippetSupport": AnyCodable(true),
                            "commitCharactersSupport": AnyCodable(true),
                            "documentationFormat": AnyCodable(["markdown", "plaintext"])
                        ])
                    ]),
                    "hover": AnyCodable([
                        "dynamicRegistration": AnyCodable(true),
                        "contentFormat": AnyCodable(["markdown", "plaintext"])
                    ]),
                    "signatureHelp": AnyCodable([
                        "dynamicRegistration": AnyCodable(true),
                        "signatureInformation": AnyCodable([
                            "documentationFormat": AnyCodable(["markdown", "plaintext"])
                        ])
                    ]),
                    "definition": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "references": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "documentHighlight": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "documentSymbol": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "codeAction": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "codeLens": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "formatting": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "rangeFormatting": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "onTypeFormatting": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "rename": AnyCodable([
                        "dynamicRegistration": AnyCodable(true)
                    ]),
                    "publishDiagnostics": AnyCodable([
                        "relatedInformation": AnyCodable(true)
                    ])
                ])
            ]),
            "initializationOptions": AnyCodable(config.initializationOptions ?? [:])
        ]
        
        let response = try await transport.sendRequest(method: "initialize", params: AnyCodable(initializeParams))
        
        guard let result = response.result?.value as? [String: Any] else {
            throw LSPError.invalidResponse("Missing result in initialize response")
        }
        
        // Parse server capabilities
        if let capabilities = result["capabilities"] as? [String: Any] {
            serverCapabilities = ServerCapabilities(from: capabilities)
        }
        
        // Send initialized notification
        try await transport.sendNotification(method: "initialized", params: nil)
        
        isInitialized = true
        await logger.logServerLifecycle(language: config.languageId, event: "Initialized", details: nil)
    }
    
    /// Handle a notification from the server
    private func handleNotification(method: String, params: AnyCodable?) async {
        switch method {
        case "textDocument/publishDiagnostics":
            if let paramsDict = params?.value as? [String: Any],
               let uri = paramsDict["uri"] as? String,
               let diagnosticsArray = paramsDict["diagnostics"] as? [[String: Any]] {
                let diagnostics = diagnosticsArray.compactMap { Diagnostic(from: $0) }
                onDiagnostics?(uri, diagnostics)
            }
        default:
            onNotification?(method, params)
        }
    }
    
    /// Open a document
    func didOpenDocument(uri: String, languageId: String, version: Int, text: String) async throws {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        await documentManager.openDocument(uri: uri, content: text, version: version)
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable([
                "uri": AnyCodable(uri),
                "languageId": AnyCodable(languageId),
                "version": AnyCodable(version),
                "text": AnyCodable(text)
            ])
        ]
        
        try await transport.sendNotification(method: "textDocument/didOpen", params: AnyCodable(params))
    }
    
    /// Update document content (incremental)
    func didChangeDocument(uri: String, version: Int, text: String) async throws {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        guard let (newVersion, edits) = await documentManager.updateDocument(uri: uri, newContent: text) else {
            return
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable([
                "uri": AnyCodable(uri),
                "version": AnyCodable(newVersion)
            ]),
            "contentChanges": AnyCodable(edits.map { edit in
                var dict: [String: AnyCodable] = ["text": AnyCodable(edit.text)]
                if let range = edit.range {
                    dict["range"] = AnyCodable([
                        "start": AnyCodable(["line": AnyCodable(range.start.line), "character": AnyCodable(range.start.character)]),
                        "end": AnyCodable(["line": AnyCodable(range.end.line), "character": AnyCodable(range.end.character)])
                    ])
                }
                if let rangeLength = edit.rangeLength {
                    dict["rangeLength"] = AnyCodable(rangeLength)
                }
                return dict
            })
        ]
        
        try await transport.sendNotification(method: "textDocument/didChange", params: AnyCodable(params))
    }
    
    /// Close a document
    func didCloseDocument(uri: String) async throws {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        await documentManager.closeDocument(uri: uri)
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable([
                "uri": AnyCodable(uri)
            ])
        ]
        
        try await transport.sendNotification(method: "textDocument/didClose", params: AnyCodable(params))
    }
    
    /// Request completion
    func completion(uri: String, position: Position) async throws -> CompletionList {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable(["uri": AnyCodable(uri)]),
            "position": AnyCodable([
                "line": AnyCodable(position.line),
                "character": AnyCodable(position.character)
            ])
        ]
        
        let response = try await transport.sendRequest(method: "textDocument/completion", params: AnyCodable(params))
        
        guard let result = response.result?.value else {
            return CompletionList(isIncomplete: false, items: [])
        }
        
        // Handle both CompletionItem[] and CompletionList
        if let itemsArray = result as? [[String: Any]] {
            let items = itemsArray.compactMap { CompletionItem(from: $0) }
            return CompletionList(isIncomplete: false, items: items)
        } else if let completionList = result as? [String: Any] {
            let isIncomplete = completionList["isIncomplete"] as? Bool ?? false
            let itemsArray = completionList["items"] as? [[String: Any]] ?? []
            let items = itemsArray.compactMap { CompletionItem(from: $0) }
            return CompletionList(isIncomplete: isIncomplete, items: items)
        }
        
        return CompletionList(isIncomplete: false, items: [])
    }
    
    /// Request hover information
    func hover(uri: String, position: Position) async throws -> Hover? {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable(["uri": AnyCodable(uri)]),
            "position": AnyCodable([
                "line": AnyCodable(position.line),
                "character": AnyCodable(position.character)
            ])
        ]
        
        let response = try await transport.sendRequest(method: "textDocument/hover", params: AnyCodable(params))
        
        guard let result = response.result?.value as? [String: Any] else {
            return nil
        }
        
        return Hover(from: result)
    }
    
    /// Request signature help
    func signatureHelp(uri: String, position: Position) async throws -> SignatureHelp? {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable(["uri": AnyCodable(uri)]),
            "position": AnyCodable([
                "line": AnyCodable(position.line),
                "character": AnyCodable(position.character)
            ])
        ]
        
        let response = try await transport.sendRequest(method: "textDocument/signatureHelp", params: AnyCodable(params))
        
        guard let result = response.result?.value as? [String: Any] else {
            return nil
        }
        
        return SignatureHelp(from: result)
    }
    
    /// Request go-to-definition
    func definition(uri: String, position: Position) async throws -> [Location] {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable(["uri": AnyCodable(uri)]),
            "position": AnyCodable([
                "line": AnyCodable(position.line),
                "character": AnyCodable(position.character)
            ])
        ]
        
        let response = try await transport.sendRequest(method: "textDocument/definition", params: AnyCodable(params))
        
        guard let result = response.result?.value else {
            return []
        }
        
        // Handle both Location and Location[]
        if let locationDict = result as? [String: Any], let location = Location(from: locationDict) {
            return [location]
        } else if let locationsArray = result as? [[String: Any]] {
            return locationsArray.compactMap { Location(from: $0) }
        }
        
        return []
    }
    
    /// Request find references
    func references(uri: String, position: Position, includeDeclaration: Bool = false) async throws -> [Location] {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable(["uri": AnyCodable(uri)]),
            "position": AnyCodable([
                "line": AnyCodable(position.line),
                "character": AnyCodable(position.character)
            ]),
            "context": AnyCodable([
                "includeDeclaration": AnyCodable(includeDeclaration)
            ])
        ]
        
        let response = try await transport.sendRequest(method: "textDocument/references", params: AnyCodable(params))
        
        guard let result = response.result?.value as? [[String: Any]] else {
            return []
        }
        
        return result.compactMap { Location(from: $0) }
    }
    
    /// Request rename
    func rename(uri: String, position: Position, newName: String) async throws -> WorkspaceEdit? {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable(["uri": AnyCodable(uri)]),
            "position": AnyCodable([
                "line": AnyCodable(position.line),
                "character": AnyCodable(position.character)
            ]),
            "newName": AnyCodable(newName)
        ]
        
        let response = try await transport.sendRequest(method: "textDocument/rename", params: AnyCodable(params))
        
        guard let result = response.result?.value as? [String: Any] else {
            return nil
        }
        
        return WorkspaceEdit(from: result)
    }
    
    /// Request code actions
    func codeAction(uri: String, range: Range, context: CodeActionContext) async throws -> [CodeAction] {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable(["uri": AnyCodable(uri)]),
            "range": AnyCodable([
                "start": AnyCodable(["line": AnyCodable(range.start.line), "character": AnyCodable(range.start.character)]),
                "end": AnyCodable(["line": AnyCodable(range.end.line), "character": AnyCodable(range.end.character)])
            ]),
            "context": AnyCodable([
                "diagnostics": AnyCodable(context.diagnostics.map { diag in
                    var dict: [String: AnyCodable] = [
                        "range": AnyCodable([
                            "start": AnyCodable(["line": AnyCodable(diag.range.start.line), "character": AnyCodable(diag.range.start.character)]),
                            "end": AnyCodable(["line": AnyCodable(diag.range.end.line), "character": AnyCodable(diag.range.end.character)])
                        ]),
                        "message": AnyCodable(diag.message)
                    ]
                    if let severity = diag.severity {
                        dict["severity"] = AnyCodable(severity.rawValue)
                    }
                    return dict
                }),
                "only": AnyCodable(context.only?.map { $0.rawValue })
            ])
        ]
        
        let response = try await transport.sendRequest(method: "textDocument/codeAction", params: AnyCodable(params))
        
        guard let result = response.result?.value as? [[String: Any]] else {
            return []
        }
        
        return result.compactMap { CodeAction(from: $0) }
    }
    
    /// Request document formatting
    func formatting(uri: String, options: FormattingOptions) async throws -> [TextEdit] {
        guard let transport = transport, isInitialized else {
            throw LSPError.connectionLost
        }
        
        let params: [String: AnyCodable] = [
            "textDocument": AnyCodable(["uri": AnyCodable(uri)]),
            "options": AnyCodable([
                "tabSize": AnyCodable(options.tabSize),
                "insertSpaces": AnyCodable(options.insertSpaces)
            ])
        ]
        
        let response = try await transport.sendRequest(method: "textDocument/formatting", params: AnyCodable(params))
        
        guard let result = response.result?.value as? [[String: Any]] else {
            return []
        }
        
        return result.compactMap { TextEdit(from: $0) }
    }
    
    /// Shutdown the session
    func shutdown() async throws {
        guard let transport = transport, isInitialized else {
            return
        }
        
        _ = try await transport.sendRequest(method: "shutdown", params: nil)
        try await transport.sendNotification(method: "exit", params: nil)
        
        process?.terminate()
        process = nil
        await transport.close()
        self.transport = nil
        isInitialized = false
        
        await logger.logServerLifecycle(language: config.languageId, event: "Shutdown", details: nil)
    }
}

// MARK: - Helper Extensions for Decoding

extension Diagnostic {
    init?(from dict: [String: Any]) {
        guard let message = dict["message"] as? String,
              let rangeDict = dict["range"] as? [String: Any],
              let range = Range(from: rangeDict) else {
            return nil
        }
        
        self.range = range
        self.message = message
        self.severity = (dict["severity"] as? Int).flatMap { DiagnosticSeverity(rawValue: $0) }
        self.source = dict["source"] as? String
        self.code = (dict["code"] as? Int).map { .int($0) } ?? (dict["code"] as? String).map { .string($0) }
        self.tags = (dict["tags"] as? [Int]).flatMap { tags in
            tags.compactMap { DiagnosticTag(rawValue: $0) }
        }
    }
}

extension Range {
    init?(from dict: [String: Any]) {
        guard let startDict = dict["start"] as? [String: Any],
              let endDict = dict["end"] as? [String: Any],
              let startLine = startDict["line"] as? Int,
              let startChar = startDict["character"] as? Int,
              let endLine = endDict["line"] as? Int,
              let endChar = endDict["character"] as? Int else {
            return nil
        }
        
        self.start = Position(line: startLine, character: startChar)
        self.end = Position(line: endLine, character: endChar)
    }
}

extension CompletionItem {
    init?(from dict: [String: Any]) {
        guard let label = dict["label"] as? String else {
            return nil
        }
        
        self.label = label
        self.kind = (dict["kind"] as? Int).flatMap { CompletionItemKind(rawValue: $0) }
        self.detail = dict["detail"] as? String
        self.documentation = (dict["documentation"] as? String).map { .string($0) } ?? (dict["documentation"] as? [String: Any]).flatMap { MarkupContent(from: $0) }.map { .markdown($0) }
        self.deprecated = dict["deprecated"] as? Bool
        self.insertText = dict["insertText"] as? String
        self.insertTextFormat = (dict["insertTextFormat"] as? Int).flatMap { InsertTextFormat(rawValue: $0) }
    }
}

extension MarkupContent {
    init?(from dict: [String: Any]) {
        guard let value = dict["value"] as? String,
              let kindString = dict["kind"] as? String,
              let kind = MarkupKind(rawValue: kindString) else {
            return nil
        }
        
        self.kind = kind
        self.value = value
    }
}

extension Hover {
    init?(from dict: [String: Any]) {
        guard let contents = dict["contents"] else {
            return nil
        }
        
        if let string = contents as? String {
            self.contents = .string(string)
        } else if let markupDict = contents as? [String: Any], let markup = MarkupContent(from: markupDict) {
            self.contents = .markup(markup)
        } else if let array = contents as? [[String: Any]] {
            let markups = array.compactMap { MarkupContent(from: $0) }
            self.contents = .array(markups)
        } else {
            return nil
        }
        
        self.range = (dict["range"] as? [String: Any]).flatMap { Range(from: $0) }
    }
}

extension Location {
    init?(from dict: [String: Any]) {
        guard let uri = dict["uri"] as? String,
              let rangeDict = dict["range"] as? [String: Any],
              let range = Range(from: rangeDict) else {
            return nil
        }
        
        self.uri = uri
        self.range = range
    }
}

extension WorkspaceEdit {
    init?(from dict: [String: Any]) {
        if let changes = dict["changes"] as? [String: [[String: Any]]] {
            var edits: [String: [TextEdit]] = [:]
            for (uri, editArray) in changes {
                edits[uri] = editArray.compactMap { TextEdit(from: $0) }
            }
            self.changes = edits
            self.documentChanges = nil
        } else {
            self.changes = nil
            self.documentChanges = nil
        }
    }
}

extension TextEdit {
    init?(from dict: [String: Any]) {
        guard let newText = dict["newText"] as? String,
              let rangeDict = dict["range"] as? [String: Any],
              let range = Range(from: rangeDict) else {
            return nil
        }
        
        self.range = range
        self.newText = newText
    }
}

extension SignatureHelp {
    init?(from dict: [String: Any]) {
        guard let signaturesArray = dict["signatures"] as? [[String: Any]] else {
            return nil
        }
        
        self.signatures = signaturesArray.compactMap { SignatureInformation(from: $0) }
        self.activeSignature = dict["activeSignature"] as? Int
        self.activeParameter = dict["activeParameter"] as? Int
    }
}

extension SignatureInformation {
    init?(from dict: [String: Any]) {
        guard let label = dict["label"] as? String else {
            return nil
        }
        
        self.label = label
        self.documentation = (dict["documentation"] as? String).map { .string($0) } ?? (dict["documentation"] as? [String: Any]).flatMap { MarkupContent(from: $0) }.map { .markdown($0) }
        self.parameters = (dict["parameters"] as? [[String: Any]]).map { $0.compactMap { ParameterInformation(from: $0) } }
        self.activeParameter = dict["activeParameter"] as? Int
    }
}

extension ParameterInformation {
    init?(from dict: [String: Any]) {
        guard let label = dict["label"] else {
            return nil
        }
        
        if let string = label as? String {
            self.label = .string(string)
        } else if let array = label as? [Int], array.count == 2 {
            self.label = .tuple(start: array[0], end: array[1])
        } else {
            return nil
        }
        
        self.documentation = (dict["documentation"] as? String).map { .string($0) } ?? (dict["documentation"] as? [String: Any]).flatMap { MarkupContent(from: $0) }.map { .markdown($0) }
    }
}

extension CodeAction {
    init?(from dict: [String: Any]) {
        guard let title = dict["title"] as? String else {
            return nil
        }
        
        self.title = title
        self.kind = (dict["kind"] as? String).flatMap { CodeActionKind(rawValue: $0) }
        self.diagnostics = (dict["diagnostics"] as? [[String: Any]]).map { $0.compactMap { Diagnostic(from: $0) } }
        self.isPreferred = dict["isPreferred"] as? Bool
        self.edit = (dict["edit"] as? [String: Any]).flatMap { WorkspaceEdit(from: $0) }
        self.command = (dict["command"] as? [String: Any]).flatMap { Command(from: $0) }
    }
}

extension Command {
    init?(from dict: [String: Any]) {
        guard let title = dict["title"] as? String,
              let command = dict["command"] as? String else {
            return nil
        }
        
        self.title = title
        self.command = command
        self.arguments = (dict["arguments"] as? [Any]).map { $0.map { AnyCodable($0) } }
    }
}

// MARK: - Server Capabilities

struct ServerCapabilities {
    var textDocumentSync: TextDocumentSyncOptions?
    var completionProvider: CompletionOptions?
    var hoverProvider: Bool?
    var signatureHelpProvider: SignatureHelpOptions?
    var definitionProvider: Bool?
    var referencesProvider: Bool?
    var renameProvider: RenameOptions?
    var codeActionProvider: CodeActionOptions?
    var documentFormattingProvider: Bool?
    
    init(from dict: [String: Any]) {
        // Parse capabilities (simplified)
        self.textDocumentSync = (dict["textDocumentSync"] as? [String: Any]).map { TextDocumentSyncOptions(from: $0) }
        self.completionProvider = (dict["completionProvider"] as? [String: Any]).map { CompletionOptions(from: $0) }
        self.hoverProvider = dict["hoverProvider"] as? Bool
        self.signatureHelpProvider = (dict["signatureHelpProvider"] as? [String: Any]).map { SignatureHelpOptions(from: $0) }
        self.definitionProvider = dict["definitionProvider"] as? Bool
        self.referencesProvider = dict["referencesProvider"] as? Bool
        self.renameProvider = (dict["renameProvider"] as? [String: Any]).map { RenameOptions(from: $0) }
        self.codeActionProvider = (dict["codeActionProvider"] as? [String: Any]).map { CodeActionOptions(from: $0) }
        self.documentFormattingProvider = dict["documentFormattingProvider"] as? Bool
    }
}

struct TextDocumentSyncOptions {
    var openClose: Bool?
    var change: Int?
    var willSave: Bool?
    var willSaveWaitUntil: Bool?
    var save: SaveOptions?
    
    init(from dict: [String: Any]) {
        self.openClose = dict["openClose"] as? Bool
        self.change = dict["change"] as? Int
        self.willSave = dict["willSave"] as? Bool
        self.willSaveWaitUntil = dict["willSaveWaitUntil"] as? Bool
        self.save = (dict["save"] as? [String: Any]).map { SaveOptions(from: $0) }
    }
}

struct SaveOptions {
    var includeText: Bool?
    
    init(from dict: [String: Any]) {
        self.includeText = dict["includeText"] as? Bool
    }
}

struct CompletionOptions {
    var triggerCharacters: [String]?
    var allCommitCharacters: [String]?
    var resolveProvider: Bool?
    
    init(from dict: [String: Any]) {
        self.triggerCharacters = dict["triggerCharacters"] as? [String]
        self.allCommitCharacters = dict["allCommitCharacters"] as? [String]
        self.resolveProvider = dict["resolveProvider"] as? Bool
    }
}

struct SignatureHelpOptions {
    var triggerCharacters: [String]?
    var retriggerCharacters: [String]?
    
    init(from dict: [String: Any]) {
        self.triggerCharacters = dict["triggerCharacters"] as? [String]
        self.retriggerCharacters = dict["retriggerCharacters"] as? [String]
    }
}

struct RenameOptions {
    var prepareProvider: Bool?
    
    init(from dict: [String: Any]) {
        self.prepareProvider = dict["prepareProvider"] as? Bool
    }
}

struct CodeActionOptions {
    var codeActionKinds: [String]?
    var resolveProvider: Bool?
    
    init(from dict: [String: Any]) {
        self.codeActionKinds = dict["codeActionKinds"] as? [String]
        self.resolveProvider = dict["resolveProvider"] as? Bool
    }
}

// MARK: - Code Action Context

struct CodeActionContext {
    var diagnostics: [Diagnostic]
    var only: [CodeActionKind]?
}
