import Foundation

/// Central coordinator for all LSP operations
actor LSPManager {
    static let shared = LSPManager()
    
    private let serverPool = LSPServerPool()
    private let cache = LSPCache()
    private let debouncer = LSPDebouncer()
    private let logger = LSPLogger.shared
    
    private var configs: [String: LanguageServerConfig] = [:]
    private var projectRoot: String?
    
    private var cleanupTask: Task<Void, Never>?
    
    private init() {
        // Initialize default configurations
        configs["swift"] = .swift()
        configs["typescript"] = .typescript()
        configs["javascript"] = .typescript() // Use TypeScript server for JS
        configs["python"] = .python()
        configs["go"] = .go()
        configs["rust"] = .rust()
        configs["cpp"] = .cpp()
        configs["c"] = .cpp() // Use clangd for C
        configs["html"] = .html()
        configs["css"] = .css()
        
        // Start cleanup task
        startCleanupTask()
    }
    
    /// Set the project root
    func setProjectRoot(_ root: String?) {
        projectRoot = root
    }
    
    /// Register or update a language server configuration
    func registerConfig(_ config: LanguageServerConfig) {
        configs[config.languageId] = config
    }
    
    /// Get configuration for a language
    func getConfig(languageId: String) -> LanguageServerConfig? {
        return configs[languageId]
    }
    
    /// Get or create a session for a language
    private func getSession(languageId: String) async throws -> LSPSession {
        guard let config = configs[languageId], config.isEnabled else {
            throw LSPError.serverNotFound(languageId)
        }
        
        let session = try await serverPool.getSession(
            languageId: languageId,
            config: config,
            projectRoot: projectRoot
        )
        
        await serverPool.updateActivity(languageId: languageId)
        
        return session
    }
    
    /// Detect language from file extension (nonisolated for synchronous access)
    nonisolated func detectLanguage(from filePath: String) -> String? {
        let ext = (filePath as NSString).pathExtension.lowercased()
        
        switch ext {
        case "swift":
            return "swift"
        case "ts", "tsx":
            return "typescript"
        case "js", "jsx", "mjs", "cjs":
            return "javascript"
        case "py":
            return "python"
        case "go":
            return "go"
        case "rs":
            return "rust"
        case "cpp", "cc", "cxx", "c++", "hpp":
            return "cpp"
        case "c", "h":
            return "c"
        case "html", "htm":
            return "html"
        case "css", "scss", "sass":
            return "css"
        default:
            return nil
        }
    }
    
    /// Open a document
    func didOpenDocument(uri: String, languageId: String?, version: Int, text: String) async throws {
        let langId = languageId ?? detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return // Don't open plaintext files
        }
        
        let session = try await getSession(languageId: langId)
        
        // Set diagnostics callback
        await session.setDiagnosticsCallback { [weak self] uri, diagnostics in
            Task { @MainActor in
                await self?.handleDiagnostics(uri: uri, diagnostics: diagnostics)
            }
        }
        
        try await session.didOpenDocument(uri: uri, languageId: langId, version: version, text: text)
    }
    
    /// Update document content (debounced)
    func didChangeDocument(uri: String, version: Int, text: String) async {
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return
        }
        
        // Invalidate cache
        await cache.invalidateDiagnostics(uri: uri)
        
        // Debounce the change notification
        await debouncer.throttleDiagnostics(key: uri) {
            do {
                let session = try await self.getSession(languageId: langId)
                try await session.didChangeDocument(uri: uri, version: version, text: text)
            } catch {
                await self.logger.logServerLifecycle(language: langId, event: "Change failed", details: error.localizedDescription)
            }
        }
    }
    
    /// Close a document
    func didCloseDocument(uri: String) async throws {
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return
        }
        
        // Cancel any pending operations
        await debouncer.cancel(key: uri)
        
        // Invalidate cache
        await cache.invalidate(uri: uri)
        
        let session = try await getSession(languageId: langId)
        try await session.didCloseDocument(uri: uri)
    }
    
    /// Request completion (debounced and cached)
    func completion(uri: String, position: Position) async throws -> CompletionList {
        // Check cache first
        if let cached = await cache.getCompletion(uri: uri, position: position) {
            return cached
        }
        
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return CompletionList(isIncomplete: false, items: [])
        }
        
        let cacheKey = "\(uri):\(position.line):\(position.character)"
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await debouncer.debounceCompletion(key: cacheKey) {
                    do {
                        let session = try await self.getSession(languageId: langId)
                        let result = try await session.completion(uri: uri, position: position)
                        
                        // Cache result
                        await self.cache.setCompletion(uri: uri, position: position, value: result)
                        
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Request hover (debounced and cached)
    func hover(uri: String, position: Position) async throws -> Hover? {
        // Check cache first
        if let cached = await cache.getHover(uri: uri, position: position) {
            return cached
        }
        
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return nil
        }
        
        let cacheKey = "\(uri):\(position.line):\(position.character)"
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await debouncer.debounceHover(key: cacheKey) {
                    do {
                        let session = try await self.getSession(languageId: langId)
                        let result = try await session.hover(uri: uri, position: position)
                        
                        // Cache result
                        if let hover = result {
                            await self.cache.setHover(uri: uri, position: position, value: hover)
                        }
                        
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Request signature help
    func signatureHelp(uri: String, position: Position) async throws -> SignatureHelp? {
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return nil
        }
        
        let session = try await getSession(languageId: langId)
        return try await session.signatureHelp(uri: uri, position: position)
    }
    
    /// Request go-to-definition
    func definition(uri: String, position: Position) async throws -> [Location] {
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return []
        }
        
        let session = try await getSession(languageId: langId)
        return try await session.definition(uri: uri, position: position)
    }
    
    /// Request find references
    func references(uri: String, position: Position, includeDeclaration: Bool = false) async throws -> [Location] {
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return []
        }
        
        let session = try await getSession(languageId: langId)
        return try await session.references(uri: uri, position: position, includeDeclaration: includeDeclaration)
    }
    
    /// Request rename
    func rename(uri: String, position: Position, newName: String) async throws -> WorkspaceEdit? {
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return nil
        }
        
        let session = try await getSession(languageId: langId)
        return try await session.rename(uri: uri, position: position, newName: newName)
    }
    
    /// Request code actions
    func codeAction(uri: String, range: Range, context: CodeActionContext) async throws -> [CodeAction] {
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return []
        }
        
        let session = try await getSession(languageId: langId)
        return try await session.codeAction(uri: uri, range: range, context: context)
    }
    
    /// Request document formatting
    func formatting(uri: String, options: FormattingOptions) async throws -> [TextEdit] {
        let langId = detectLanguage(from: uri) ?? "plaintext"
        
        guard langId != "plaintext" else {
            return []
        }
        
        let session = try await getSession(languageId: langId)
        return try await session.formatting(uri: uri, options: options)
    }
    
    /// Callback for diagnostics updates (set by EditorViewModel)
    private var onDiagnostics: ((String, [Diagnostic]) -> Void)?
    
    /// Set callback for diagnostics updates
    func setDiagnosticsCallback(_ callback: @escaping (String, [Diagnostic]) -> Void) {
        onDiagnostics = callback
    }
    
    /// Handle diagnostics from a session
    private func handleDiagnostics(uri: String, diagnostics: [Diagnostic]) async {
        // Cache diagnostics
        await cache.setDiagnostics(uri: uri, value: diagnostics)
        
        // Notify callback
        onDiagnostics?(uri, diagnostics)
    }
    
    /// Start periodic cleanup task
    private func startCleanupTask() {
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // Every minute
                await serverPool.cleanupIdleServers()
            }
        }
    }
    
    /// Shutdown all servers
    func shutdown() async {
        cleanupTask?.cancel()
        await serverPool.shutdownAll()
        await cache.clear()
        await debouncer.cancelAll()
    }
    
    /// Get server status
    func getServerStatus(languageId: String) async -> LSPServerPool.ServerStatus {
        return await serverPool.getServerStatus(languageId: languageId)
    }
    
    /// Get cache statistics
    func getCacheStats() async -> (size: Int, maxSize: Int, entries: Int) {
        return await cache.getStats()
    }
}
