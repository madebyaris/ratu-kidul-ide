import Foundation

/// Manages a pool of language server processes with resource limits
actor LSPServerPool {
    private var sessions: [String: LSPSession] = [:]
    private var lastActivity: [String: Date] = [:]
    private var restartAttempts: [String: Int] = [:]
    
    private let maxConcurrentServers = 5
    private let idleTimeout: TimeInterval = 300 // 5 minutes
    private let maxRestartAttempts = 3
    
    private let logger = LSPLogger.shared
    
    /// Get or create a session for a language
    func getSession(
        languageId: String,
        config: LanguageServerConfig,
        projectRoot: String?
    ) async throws -> LSPSession {
        // Check if session exists and is still valid
        if let session = sessions[languageId] {
            lastActivity[languageId] = Date()
            return session
        }
        
        // Check resource limits
        if sessions.count >= maxConcurrentServers {
            // Evict least recently used server
            try await evictLeastRecentlyUsed()
        }
        
        // Create new session
        let session = LSPSession(config: config, projectRoot: projectRoot)
        
        do {
            try await session.start()
            sessions[languageId] = session
            lastActivity[languageId] = Date()
            restartAttempts[languageId] = 0
            
            await logger.logServerLifecycle(language: languageId, event: "Started", details: nil)
        } catch {
            // Handle startup failure
            let attempts = restartAttempts[languageId] ?? 0
            restartAttempts[languageId] = attempts + 1
            
            if attempts < maxRestartAttempts {
                await logger.logServerLifecycle(language: languageId, event: "Start failed, will retry", details: "Attempt \(attempts + 1)")
                throw error
            } else {
                await logger.logServerLifecycle(language: languageId, event: "Start failed, max attempts reached", details: nil)
                throw LSPError.serverCrashed(languageId)
            }
        }
        
        return session
    }
    
    /// Evict the least recently used server
    private func evictLeastRecentlyUsed() async throws {
        guard let (languageId, _) = lastActivity.min(by: { $0.value < $1.value }) else {
            return
        }
        
        await logger.logServerLifecycle(language: languageId, event: "Evicting (LRU)", details: nil)
        
        if let session = sessions[languageId] {
            try? await session.shutdown()
        }
        
        sessions.removeValue(forKey: languageId)
        lastActivity.removeValue(forKey: languageId)
        restartAttempts.removeValue(forKey: languageId)
    }
    
    /// Update activity timestamp for a language
    func updateActivity(languageId: String) {
        lastActivity[languageId] = Date()
    }
    
    /// Clean up idle servers
    func cleanupIdleServers() async {
        let now = Date()
        
        for (languageId, lastActive) in lastActivity {
            if now.timeIntervalSince(lastActive) > idleTimeout {
                await logger.logServerLifecycle(language: languageId, event: "Shutting down (idle)", details: nil)
                
                if let session = sessions[languageId] {
                    try? await session.shutdown()
                }
                
                sessions.removeValue(forKey: languageId)
                lastActivity.removeValue(forKey: languageId)
                restartAttempts.removeValue(forKey: languageId)
            }
        }
    }
    
    /// Shutdown a specific server
    func shutdown(languageId: String) async {
        if let session = sessions[languageId] {
            try? await session.shutdown()
            sessions.removeValue(forKey: languageId)
            lastActivity.removeValue(forKey: languageId)
            restartAttempts.removeValue(forKey: languageId)
            
            await logger.logServerLifecycle(language: languageId, event: "Shutdown", details: nil)
        }
    }
    
    /// Shutdown all servers
    func shutdownAll() async {
        for (languageId, session) in sessions {
            try? await session.shutdown()
            await logger.logServerLifecycle(language: languageId, event: "Shutdown", details: nil)
        }
        
        sessions.removeAll()
        lastActivity.removeAll()
        restartAttempts.removeAll()
    }
    
    /// Get active server count
    func getActiveServerCount() -> Int {
        return sessions.count
    }
    
    /// Get server status
    func getServerStatus(languageId: String) -> ServerStatus {
        if sessions[languageId] != nil {
            return .running
        } else {
            return .stopped
        }
    }
    
    enum ServerStatus {
        case running
        case stopped
    }
}
