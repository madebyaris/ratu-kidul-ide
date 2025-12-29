import Foundation

/// LRU cache for LSP responses
actor LSPCache {
    private struct CacheEntry {
        let key: String
        let value: Any
        let timestamp: Date
        let size: Int // Estimated size in bytes
        
        init(key: String, value: Any, size: Int) {
            self.key = key
            self.value = value
            self.timestamp = Date()
            self.size = size
        }
    }
    
    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = [] // Most recently used at end
    
    private let maxSize: Int = 50 * 1024 * 1024 // 50MB
    private var currentSize: Int = 0
    
    private let hoverTTL: TimeInterval = 30.0 // 30 seconds
    
    /// Get a cached completion list
    func getCompletion(uri: String, position: Position) -> CompletionList? {
        let key = "completion:\(uri):\(position.line):\(position.character)"
        
        guard let entry = cache[key] else {
            return nil
        }
        
        // Move to end (most recently used)
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        
        return entry.value as? CompletionList
    }
    
    /// Cache a completion list
    func setCompletion(uri: String, position: Position, value: CompletionList) {
        let key = "completion:\(uri):\(position.line):\(position.character)"
        
        // Estimate size (rough approximation)
        let size = estimateSize(value)
        
        // Remove old entry if exists
        if let oldEntry = cache[key] {
            currentSize -= oldEntry.size
            accessOrder.removeAll { $0 == key }
        }
        
        // Add new entry
        cache[key] = CacheEntry(key: key, value: value, size: size)
        accessOrder.append(key)
        currentSize += size
        
        // Evict if needed
        evictIfNeeded()
    }
    
    /// Get cached hover content
    func getHover(uri: String, position: Position) -> Hover? {
        let key = "hover:\(uri):\(position.line):\(position.character)"
        
        guard let entry = cache[key] else {
            return nil
        }
        
        // Check TTL
        if Date().timeIntervalSince(entry.timestamp) > hoverTTL {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            currentSize -= entry.size
            return nil
        }
        
        // Move to end (most recently used)
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        
        return entry.value as? Hover
    }
    
    /// Cache hover content
    func setHover(uri: String, position: Position, value: Hover) {
        let key = "hover:\(uri):\(position.line):\(position.character)"
        
        // Estimate size
        let size = estimateSize(value)
        
        // Remove old entry if exists
        if let oldEntry = cache[key] {
            currentSize -= oldEntry.size
            accessOrder.removeAll { $0 == key }
        }
        
        // Add new entry
        cache[key] = CacheEntry(key: key, value: value, size: size)
        accessOrder.append(key)
        currentSize += size
        
        // Evict if needed
        evictIfNeeded()
    }
    
    /// Get cached diagnostics
    func getDiagnostics(uri: String) -> [Diagnostic]? {
        let key = "diagnostics:\(uri)"
        
        guard let entry = cache[key] else {
            return nil
        }
        
        // Move to end (most recently used)
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        
        return entry.value as? [Diagnostic]
    }
    
    /// Cache diagnostics
    func setDiagnostics(uri: String, value: [Diagnostic]) {
        let key = "diagnostics:\(uri)"
        
        // Estimate size
        let size = estimateSize(value)
        
        // Remove old entry if exists
        if let oldEntry = cache[key] {
            currentSize -= oldEntry.size
            accessOrder.removeAll { $0 == key }
        }
        
        // Add new entry
        cache[key] = CacheEntry(key: key, value: value, size: size)
        accessOrder.append(key)
        currentSize += size
        
        // Evict if needed
        evictIfNeeded()
    }
    
    /// Invalidate diagnostics for a URI (called when file changes)
    func invalidateDiagnostics(uri: String) {
        let key = "diagnostics:\(uri)"
        
        if let entry = cache[key] {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            currentSize -= entry.size
        }
    }
    
    /// Invalidate all cache entries for a URI
    func invalidate(uri: String) {
        let keysToRemove = cache.keys.filter { $0.hasPrefix("completion:\(uri):") || 
                                                 $0.hasPrefix("hover:\(uri):") ||
                                                 $0 == "diagnostics:\(uri)" }
        
        for key in keysToRemove {
            if let entry = cache[key] {
                currentSize -= entry.size
            }
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
    
    /// Clear all cache
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
        currentSize = 0
    }
    
    /// Evict least recently used entries if cache exceeds max size
    private func evictIfNeeded() {
        while currentSize > maxSize && !accessOrder.isEmpty {
            // Remove least recently used (first in accessOrder)
            let keyToRemove = accessOrder.removeFirst()
            
            if let entry = cache[keyToRemove] {
                currentSize -= entry.size
                cache.removeValue(forKey: keyToRemove)
            }
        }
    }
    
    /// Estimate size of a value in bytes (rough approximation)
    private func estimateSize(_ value: Any) -> Int {
        if let completionList = value as? CompletionList {
            // Rough estimate: ~200 bytes per completion item
            return completionList.items.count * 200
        } else if let hover = value as? Hover {
            // Estimate based on content length
            switch hover.contents {
            case .string(let str):
                return str.utf8.count
            case .markup(let markup):
                return markup.value.utf8.count
            case .array(let markups):
                return markups.reduce(0) { $0 + $1.value.utf8.count }
            }
        } else if let diagnostics = value as? [Diagnostic] {
            // Rough estimate: ~300 bytes per diagnostic
            return diagnostics.count * 300
        }
        
        return 1024 // Default estimate
    }
    
    /// Get cache statistics
    func getStats() -> (size: Int, maxSize: Int, entries: Int) {
        return (size: currentSize, maxSize: maxSize, entries: cache.count)
    }
}
