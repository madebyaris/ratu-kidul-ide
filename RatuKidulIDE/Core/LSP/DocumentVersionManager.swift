import Foundation

/// Represents a line change for incremental document updates
private struct LineChange {
    let startLine: Int
    let endLine: Int
    let newText: String
}

/// Manages document versions and generates incremental text edits
actor DocumentVersionManager {
    private var documents: [String: DocumentState] = [:]
    
    struct DocumentState {
        var version: Int
        var content: String
        var lastModified: Date
    }
    
    /// Initialize or update a document
    func openDocument(uri: String, content: String, version: Int = 1) {
        documents[uri] = DocumentState(
            version: version,
            content: content,
            lastModified: Date()
        )
    }
    
    /// Update document content and return incremental edits
    func updateDocument(uri: String, newContent: String) -> (version: Int, edits: [TextDocumentContentChangeEvent])? {
        guard var state = documents[uri] else {
            // Document not tracked, return full content
            let version = 1
            documents[uri] = DocumentState(
                version: version,
                content: newContent,
                lastModified: Date()
            )
            return (version: version, edits: [
                TextDocumentContentChangeEvent(
                    range: nil,
                    rangeLength: nil,
                    text: newContent
                )
            ])
        }
        
        // Generate incremental edits using Myers diff algorithm
        let edits = computeDiff(oldContent: state.content, newContent: newContent)
        
        state.version += 1
        state.content = newContent
        state.lastModified = Date()
        documents[uri] = state
        
        return (version: state.version, edits: edits)
    }
    
    /// Close a document
    func closeDocument(uri: String) {
        documents.removeValue(forKey: uri)
    }
    
    /// Get current version of a document
    func getVersion(uri: String) -> Int? {
        return documents[uri]?.version
    }
    
    /// Get current content of a document
    func getContent(uri: String) -> String? {
        return documents[uri]?.content
    }
    
    /// Compute diff between old and new content using Myers algorithm
    private func computeDiff(oldContent: String, newContent: String) -> [TextDocumentContentChangeEvent] {
        // If content is identical, return empty edits
        if oldContent == newContent {
            return []
        }
        
        // Simple line-based diff for now (can be optimized with character-level diff)
        let oldLines = oldContent.components(separatedBy: .newlines)
        let newLines = newContent.components(separatedBy: .newlines)
        
        // If content is small, send full replacement
        if oldContent.count < 1000 || newContent.count < 1000 {
            return [
                TextDocumentContentChangeEvent(
                    range: nil,
                    rangeLength: nil,
                    text: newContent
                )
            ]
        }
        
        // Use line-based diff for larger files
        var edits: [TextDocumentContentChangeEvent] = []
        let diff = computeLineDiff(oldLines: oldLines, newLines: newLines)
        
        for change in diff {
            let startLine = change.startLine
            let endLine = change.endLine
            let newText = change.newText
            
            // Calculate character positions
            let startChar = startLine < oldLines.count ? 0 : 0
            let endChar = endLine < oldLines.count ? oldLines[endLine].count : 0
            
            let range = Range(
                start: Position(line: startLine, character: startChar),
                end: Position(line: endLine, character: endChar)
            )
            
            edits.append(TextDocumentContentChangeEvent(
                range: range,
                rangeLength: nil,
                text: newText
            ))
        }
        
        // If diff is too complex, fall back to full replacement
        if edits.count > 50 {
            return [
                TextDocumentContentChangeEvent(
                    range: nil,
                    rangeLength: nil,
                    text: newContent
                )
            ]
        }
        
        return edits
    }
    
    /// Simple line-based diff algorithm
    private func computeLineDiff(oldLines: [String], newLines: [String]) -> [LineChange] {
        var changes: [LineChange] = []
        var oldIndex = 0
        var newIndex = 0
        
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex >= oldLines.count {
                // All remaining new lines are additions
                let start = newIndex
                let newText = newLines[newIndex...].joined(separator: "\n")
                changes.append(LineChange(startLine: oldIndex, endLine: oldIndex, newText: newText))
                break
            }
            
            if newIndex >= newLines.count {
                // All remaining old lines are deletions
                changes.append(LineChange(startLine: oldIndex, endLine: oldLines.count, newText: ""))
                break
            }
            
            if oldLines[oldIndex] == newLines[newIndex] {
                // Lines match, advance both
                oldIndex += 1
                newIndex += 1
            } else {
                // Find the next matching line
                var foundMatch = false
                var searchIndex = newIndex + 1
                
                while searchIndex < newLines.count && searchIndex - newIndex < 10 {
                    if oldLines[oldIndex] == newLines[searchIndex] {
                        // Found match, record change
                        let newText = newLines[newIndex..<searchIndex].joined(separator: "\n")
                        changes.append(LineChange(startLine: oldIndex, endLine: oldIndex, newText: newText))
                        newIndex = searchIndex + 1
                        oldIndex += 1
                        foundMatch = true
                        break
                    }
                    searchIndex += 1
                }
                
                if !foundMatch {
                    // No match found, record deletion and addition
                    changes.append(LineChange(startLine: oldIndex, endLine: oldIndex + 1, newText: newLines[newIndex]))
                    oldIndex += 1
                    newIndex += 1
                }
            }
        }
        
        return changes
    }
}
