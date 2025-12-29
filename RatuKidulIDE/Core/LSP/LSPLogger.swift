import Foundation
import os.log

/// Structured logging for LSP operations
actor LSPLogger {
    static let shared = LSPLogger()
    
    private let logger = Logger(subsystem: "com.ratukidul.ide.lsp", category: "LSP")
    private var isDebugEnabled = false
    private var performanceMetrics: [String: [TimeInterval]] = [:]
    
    private init() {}
    
    /// Enable or disable debug logging
    func setDebugEnabled(_ enabled: Bool) {
        isDebugEnabled = enabled
    }
    
    /// Log a request being sent to the language server
    func logRequest(method: String, id: Int, params: [String: Any]? = nil) {
        guard isDebugEnabled else { return }
        logger.debug("→ Request: \(method) (id: \(id))")
        if let params = params {
            logger.debug("  Params: \(String(describing: params))")
        }
    }
    
    /// Log a response received from the language server
    func logResponse(method: String, id: Int, duration: TimeInterval? = nil) {
        if let duration = duration {
            logger.debug("← Response: \(method) (id: \(id), duration: \(String(format: "%.2f", duration))ms)")
            recordMetric(method: method, duration: duration)
        } else {
            logger.debug("← Response: \(method) (id: \(id))")
        }
    }
    
    /// Log an error response
    func logError(method: String, id: Int, code: Int, message: String) {
        logger.error("✗ Error: \(method) (id: \(id), code: \(code)): \(message)")
    }
    
    /// Log a notification
    func logNotification(method: String, params: [String: Any]? = nil) {
        guard isDebugEnabled else { return }
        logger.debug("⊢ Notification: \(method)")
        if let params = params {
            logger.debug("  Params: \(String(describing: params))")
        }
    }
    
    /// Log server lifecycle events
    func logServerLifecycle(language: String, event: String, details: String? = nil) {
        logger.info("Server [\(language)]: \(event)")
        if let details = details {
            logger.debug("  \(details)")
        }
    }
    
    /// Log performance metrics
    func logPerformance(operation: String, duration: TimeInterval) {
        logger.debug("⏱ Performance: \(operation) took \(String(format: "%.2f", duration))ms")
        recordMetric(method: operation, duration: duration)
    }
    
    /// Record a performance metric
    private func recordMetric(method: String, duration: TimeInterval) {
        if performanceMetrics[method] == nil {
            performanceMetrics[method] = []
        }
        performanceMetrics[method]?.append(duration)
        
        // Keep only last 100 measurements per method
        if let metrics = performanceMetrics[method], metrics.count > 100 {
            performanceMetrics[method] = Array(metrics.suffix(100))
        }
    }
    
    /// Get performance statistics for a method
    func getPerformanceStats(method: String) -> (avg: TimeInterval, min: TimeInterval, max: TimeInterval, count: Int)? {
        guard let metrics = performanceMetrics[method], !metrics.isEmpty else {
            return nil
        }
        
        let avg = metrics.reduce(0, +) / Double(metrics.count)
        let min = metrics.min() ?? 0
        let max = metrics.max() ?? 0
        
        return (avg: avg, min: min, max: max, count: metrics.count)
    }
    
    /// Export logs for debugging
    func exportLogs() -> String {
        var output = "=== LSP Performance Metrics ===\n\n"
        
        for (method, metrics) in performanceMetrics.sorted(by: { $0.key < $1.key }) {
            if let stats = getPerformanceStats(method: method) {
                output += "\(method):\n"
                output += "  Count: \(stats.count)\n"
                output += "  Avg: \(String(format: "%.2f", stats.avg))ms\n"
                output += "  Min: \(String(format: "%.2f", stats.min))ms\n"
                output += "  Max: \(String(format: "%.2f", stats.max))ms\n\n"
            }
        }
        
        return output
    }
}
