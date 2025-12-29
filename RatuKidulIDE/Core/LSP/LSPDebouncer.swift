import Foundation

/// Debounces and throttles LSP requests to optimize performance
actor LSPDebouncer {
    private var completionTasks: [String: Task<Void, Never>] = [:]
    private var diagnosticsTasks: [String: Task<Void, Never>] = [:]
    private var hoverTasks: [String: Task<Void, Never>] = [:]
    
    private let completionDebounce: TimeInterval = 0.15 // 150ms
    private let diagnosticsThrottle: TimeInterval = 0.3 // 300ms
    private let hoverDebounce: TimeInterval = 0.1 // 100ms
    
    /// Debounce a completion request
    func debounceCompletion(
        key: String,
        delay: TimeInterval? = nil,
        operation: @escaping () async throws -> Void
    ) async {
        // Cancel previous task
        completionTasks[key]?.cancel()
        
        let delay = delay ?? completionDebounce
        
        // Create new task
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                try await operation()
            } catch is CancellationError {
                // Task was cancelled, ignore
            } catch {
                // Log error but don't propagate
                print("LSPDebouncer: Error in completion operation: \(error)")
            }
        }
        
        completionTasks[key] = task
    }
    
    /// Throttle a diagnostics update
    func throttleDiagnostics(
        key: String,
        delay: TimeInterval? = nil,
        operation: @escaping () async throws -> Void
    ) async {
        // If task exists, don't create new one (throttling)
        guard diagnosticsTasks[key] == nil || diagnosticsTasks[key]?.isCancelled == true else {
            return
        }
        
        let delay = delay ?? diagnosticsThrottle
        
        // Create new task
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                try await operation()
            } catch is CancellationError {
                // Task was cancelled, ignore
            } catch {
                // Log error but don't propagate
                print("LSPDebouncer: Error in diagnostics operation: \(error)")
            }
            
            // Clean up task reference
            diagnosticsTasks.removeValue(forKey: key)
        }
        
        diagnosticsTasks[key] = task
    }
    
    /// Debounce a hover request
    func debounceHover(
        key: String,
        delay: TimeInterval? = nil,
        operation: @escaping () async throws -> Void
    ) async {
        // Cancel previous task
        hoverTasks[key]?.cancel()
        
        let delay = delay ?? hoverDebounce
        
        // Create new task
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                try await operation()
            } catch is CancellationError {
                // Task was cancelled, ignore
            } catch {
                // Log error but don't propagate
                print("LSPDebouncer: Error in hover operation: \(error)")
            }
        }
        
        hoverTasks[key] = task
    }
    
    /// Cancel all pending operations for a key
    func cancel(key: String) {
        completionTasks[key]?.cancel()
        diagnosticsTasks[key]?.cancel()
        hoverTasks[key]?.cancel()
        
        completionTasks.removeValue(forKey: key)
        diagnosticsTasks.removeValue(forKey: key)
        hoverTasks.removeValue(forKey: key)
    }
    
    /// Cancel all pending operations
    func cancelAll() {
        for task in completionTasks.values {
            task.cancel()
        }
        for task in diagnosticsTasks.values {
            task.cancel()
        }
        for task in hoverTasks.values {
            task.cancel()
        }
        
        completionTasks.removeAll()
        diagnosticsTasks.removeAll()
        hoverTasks.removeAll()
    }
}
