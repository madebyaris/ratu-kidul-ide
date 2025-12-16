import Foundation

// MARK: - Search Tools Implementation

/// Handles search operations for the AI agent
actor SearchTools {
    static let shared = SearchTools()
    
    private let fileManager = FileManager.default
    
    /// The base project path for relative path resolution
    private(set) var projectPath: String?
    
    /// Set the project path
    func setProjectPath(_ path: String) {
        projectPath = path
    }
    
    /// Directories to skip during search
    private let skipDirectories = Set([
        "node_modules", ".git", ".build", "Pods", "DerivedData",
        ".swiftpm", "__pycache__", "venv", ".venv", ".idea",
        ".vs", "bin", "obj", "target", "dist", "build"
    ])
    
    /// File extensions to include in code search
    private let codeExtensions = Set([
        "swift", "m", "h", "mm", "c", "cpp", "hpp",
        "js", "jsx", "ts", "tsx", "mjs", "cjs",
        "py", "rb", "go", "rs", "java", "kt", "scala",
        "php", "cs", "fs", "vb",
        "html", "htm", "css", "scss", "sass", "less",
        "json", "xml", "yaml", "yml", "toml",
        "md", "txt", "sh", "bash", "zsh",
        "sql", "graphql", "prisma"
    ])
    
    private init() {}
    
    // MARK: - Path Resolution
    
    /// Resolve a path relative to the project root
    /// Returns nil if path is outside project directory (security check)
    func resolvePath(_ path: String?) -> String? {
        // If no project path is set, reject all operations
        guard let projectPath = projectPath else {
            return nil
        }
        
        let normalizedProject = (projectPath as NSString).standardizingPath
        
        // Default to project root if path is empty or nil
        guard let path = path, !path.isEmpty, path != "." else {
            return normalizedProject
        }
        
        // Handle relative paths
        if !path.hasPrefix("/") {
            let resolved = (projectPath as NSString).appendingPathComponent(path)
            let normalized = (resolved as NSString).standardizingPath
            // Ensure it's still within project
            if normalized.hasPrefix(normalizedProject) {
                return normalized
            }
            return nil
        }
        
        // Handle absolute paths - only allow if within project directory
        let normalizedPath = (path as NSString).standardizingPath
        if normalizedPath.hasPrefix(normalizedProject) {
            return normalizedPath
        }
        
        // Path is outside project directory - reject
        return nil
    }
    
    /// Get the project root path
    func getProjectRoot() -> String? {
        return projectPath
    }
    
    // MARK: - Grep Search
    
    func grepSearch(
        pattern: String,
        path: String? = nil,
        include: String? = nil,
        exclude: String? = nil,
        caseSensitive: Bool = false,
        maxResults: Int = 50
    ) async -> ToolExecutionResult {
        guard let searchPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "grep_search",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path ?? "project root")"
            )
        }
        
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: searchPath, isDirectory: &isDir) else {
            return ToolExecutionResult(
                toolName: "grep_search",
                success: false,
                output: "",
                error: "Path not found: \(path ?? "project root")"
            )
        }
        
        var results: [SearchMatch] = []
        let regex: NSRegularExpression?
        
        do {
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            // Fall back to literal search if regex is invalid
            regex = nil
        }
        
        // Parse include/exclude patterns
        let includePatterns = parseGlobPattern(include)
        let excludePatterns = parseGlobPattern(exclude)
        
        if isDir.boolValue {
            await searchDirectory(
                at: searchPath,
                pattern: pattern,
                regex: regex,
                caseSensitive: caseSensitive,
                includePatterns: includePatterns,
                excludePatterns: excludePatterns,
                results: &results,
                maxResults: maxResults
            )
        } else {
            // Search single file
            await searchFile(
                at: searchPath,
                pattern: pattern,
                regex: regex,
                caseSensitive: caseSensitive,
                results: &results,
                maxResults: maxResults
            )
        }
        
        if results.isEmpty {
            return ToolExecutionResult(
                toolName: "grep_search",
                success: true,
                output: "No matches found for: \(pattern)",
                metadata: ["pattern": pattern, "matches": 0]
            )
        }
        
        // Format results
        var output = "Found \(results.count) match(es) for '\(pattern)':\n\n"
        
        var currentFile = ""
        for match in results {
            if match.filePath != currentFile {
                currentFile = match.filePath
                let relativePath = makeRelativePath(match.filePath)
                output += "\n📄 \(relativePath)\n"
            }
            output += "  \(match.lineNumber): \(match.lineContent.trimmingCharacters(in: .whitespaces))\n"
        }
        
        if results.count >= maxResults {
            output += "\n[Results limited to \(maxResults). Use more specific patterns or path to narrow down.]"
        }
        
        return ToolExecutionResult(
            toolName: "grep_search",
            success: true,
            output: output,
            metadata: [
                "pattern": pattern,
                "matches": results.count,
                "files": Set(results.map { $0.filePath }).count
            ]
        )
    }
    
    private func searchDirectory(
        at path: String,
        pattern: String,
        regex: NSRegularExpression?,
        caseSensitive: Bool,
        includePatterns: [String],
        excludePatterns: [String],
        results: inout [SearchMatch],
        maxResults: Int
    ) async {
        guard results.count < maxResults else { return }
        
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return }
        
        for item in contents {
            guard results.count < maxResults else { return }
            
            // Skip hidden files and directories
            if item.hasPrefix(".") { continue }
            
            let itemPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
            
            if isDir.boolValue {
                // Skip excluded directories
                if skipDirectories.contains(item) { continue }
                if matchesAnyPattern(item, patterns: excludePatterns) { continue }
                
                await searchDirectory(
                    at: itemPath,
                    pattern: pattern,
                    regex: regex,
                    caseSensitive: caseSensitive,
                    includePatterns: includePatterns,
                    excludePatterns: excludePatterns,
                    results: &results,
                    maxResults: maxResults
                )
            } else {
                // Check file extension
                let ext = (item as NSString).pathExtension.lowercased()
                
                // Apply include filter
                if !includePatterns.isEmpty && !matchesAnyPattern(item, patterns: includePatterns) {
                    continue
                }
                
                // Apply exclude filter
                if matchesAnyPattern(item, patterns: excludePatterns) {
                    continue
                }
                
                // Only search code files by default
                if includePatterns.isEmpty && !codeExtensions.contains(ext) {
                    continue
                }
                
                await searchFile(
                    at: itemPath,
                    pattern: pattern,
                    regex: regex,
                    caseSensitive: caseSensitive,
                    results: &results,
                    maxResults: maxResults
                )
            }
        }
    }
    
    private func searchFile(
        at path: String,
        pattern: String,
        regex: NSRegularExpression?,
        caseSensitive: Bool,
        results: inout [SearchMatch],
        maxResults: Int
    ) async {
        guard results.count < maxResults else { return }
        
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            guard results.count < maxResults else { return }
            
            let matches: Bool
            if let regex = regex {
                let range = NSRange(line.startIndex..., in: line)
                matches = regex.firstMatch(in: line, range: range) != nil
            } else {
                // Literal search
                if caseSensitive {
                    matches = line.contains(pattern)
                } else {
                    matches = line.lowercased().contains(pattern.lowercased())
                }
            }
            
            if matches {
                results.append(SearchMatch(
                    filePath: path,
                    lineNumber: index + 1,
                    lineContent: line
                ))
            }
        }
    }
    
    // MARK: - Find Files
    
    func findFiles(pattern: String, path: String? = nil, maxResults: Int = 20) async -> ToolExecutionResult {
        guard let searchPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "find_files",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path ?? "project root")"
            )
        }
        
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: searchPath, isDirectory: &isDir), isDir.boolValue else {
            return ToolExecutionResult(
                toolName: "find_files",
                success: false,
                output: "",
                error: "Directory not found: \(path ?? "project root")"
            )
        }
        
        var results: [String] = []
        await findFilesRecursive(
            at: searchPath,
            pattern: pattern,
            results: &results,
            maxResults: maxResults
        )
        
        if results.isEmpty {
            return ToolExecutionResult(
                toolName: "find_files",
                success: true,
                output: "No files found matching: \(pattern)",
                metadata: ["pattern": pattern, "matches": 0]
            )
        }
        
        let relativePaths = results.map { makeRelativePath($0) }
        var output = "Found \(results.count) file(s) matching '\(pattern)':\n\n"
        output += relativePaths.map { "📄 \($0)" }.joined(separator: "\n")
        
        if results.count >= maxResults {
            output += "\n\n[Results limited to \(maxResults)]"
        }
        
        return ToolExecutionResult(
            toolName: "find_files",
            success: true,
            output: output,
            metadata: ["pattern": pattern, "matches": results.count]
        )
    }
    
    private func findFilesRecursive(
        at path: String,
        pattern: String,
        results: inout [String],
        maxResults: Int
    ) async {
        guard results.count < maxResults else { return }
        
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return }
        
        for item in contents {
            guard results.count < maxResults else { return }
            
            if item.hasPrefix(".") { continue }
            
            let itemPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
            
            // Match both files and directories against pattern
            if matchesGlob(item, pattern: pattern) {
                results.append(itemPath)
            }
            
            if isDir.boolValue {
                if skipDirectories.contains(item) { continue }
                
                await findFilesRecursive(
                    at: itemPath,
                    pattern: pattern,
                    results: &results,
                    maxResults: maxResults
                )
            }
        }
    }
    
    // MARK: - Find Symbol
    
    func findSymbol(symbol: String, path: String? = nil, type: String = "any") async -> ToolExecutionResult {
        guard let searchPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "find_symbol",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path ?? "project root")"
            )
        }
        
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: searchPath, isDirectory: &isDir) else {
            return ToolExecutionResult(
                toolName: "find_symbol",
                success: false,
                output: "",
                error: "Path not found: \(path ?? "project root")"
            )
        }
        
        var results: [SymbolMatch] = []
        
        if isDir.boolValue {
            await findSymbolRecursive(
                at: searchPath,
                symbol: symbol,
                symbolType: type,
                results: &results,
                maxResults: 20
            )
        } else {
            await findSymbolInFile(
                at: searchPath,
                symbol: symbol,
                symbolType: type,
                results: &results
            )
        }
        
        if results.isEmpty {
            return ToolExecutionResult(
                toolName: "find_symbol",
                success: true,
                output: "No symbol definitions found for: \(symbol)",
                metadata: ["symbol": symbol, "type": type, "matches": 0]
            )
        }
        
        var output = "Found \(results.count) definition(s) for '\(symbol)':\n\n"
        
        for match in results {
            let relativePath = makeRelativePath(match.filePath)
            output += "📍 \(match.symbolType) \(match.symbolName)\n"
            output += "   File: \(relativePath):\(match.lineNumber)\n"
            output += "   \(match.lineContent.trimmingCharacters(in: .whitespaces))\n\n"
        }
        
        return ToolExecutionResult(
            toolName: "find_symbol",
            success: true,
            output: output,
            metadata: ["symbol": symbol, "type": type, "matches": results.count]
        )
    }
    
    private func findSymbolRecursive(
        at path: String,
        symbol: String,
        symbolType: String,
        results: inout [SymbolMatch],
        maxResults: Int
    ) async {
        guard results.count < maxResults else { return }
        
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return }
        
        for item in contents {
            guard results.count < maxResults else { return }
            
            if item.hasPrefix(".") { continue }
            
            let itemPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
            
            if isDir.boolValue {
                if skipDirectories.contains(item) { continue }
                
                await findSymbolRecursive(
                    at: itemPath,
                    symbol: symbol,
                    symbolType: symbolType,
                    results: &results,
                    maxResults: maxResults
                )
            } else {
                let ext = (item as NSString).pathExtension.lowercased()
                if codeExtensions.contains(ext) {
                    await findSymbolInFile(
                        at: itemPath,
                        symbol: symbol,
                        symbolType: symbolType,
                        results: &results
                    )
                }
            }
        }
    }
    
    private func findSymbolInFile(
        at path: String,
        symbol: String,
        symbolType: String,
        results: inout [SymbolMatch]
    ) async {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        
        let ext = (path as NSString).pathExtension.lowercased()
        let patterns = getSymbolPatterns(for: ext, symbol: symbol, type: symbolType)
        
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            for (patternType, regex) in patterns {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    results.append(SymbolMatch(
                        filePath: path,
                        lineNumber: index + 1,
                        lineContent: line,
                        symbolName: symbol,
                        symbolType: patternType
                    ))
                    break // Only match once per line
                }
            }
        }
    }
    
    private func getSymbolPatterns(for ext: String, symbol: String, type: String) -> [(String, NSRegularExpression)] {
        var patterns: [(String, NSRegularExpression)] = []
        let escapedSymbol = NSRegularExpression.escapedPattern(for: symbol)
        
        // Swift patterns
        if ext == "swift" {
            if type == "any" || type == "function" {
                if let regex = try? NSRegularExpression(pattern: "func\\s+\(escapedSymbol)\\s*[<(]", options: []) {
                    patterns.append(("func", regex))
                }
            }
            if type == "any" || type == "class" {
                if let regex = try? NSRegularExpression(pattern: "class\\s+\(escapedSymbol)\\s*[:{<]?", options: []) {
                    patterns.append(("class", regex))
                }
            }
            if type == "any" || type == "struct" {
                if let regex = try? NSRegularExpression(pattern: "struct\\s+\(escapedSymbol)\\s*[:{<]?", options: []) {
                    patterns.append(("struct", regex))
                }
            }
            if type == "any" || type == "enum" {
                if let regex = try? NSRegularExpression(pattern: "enum\\s+\(escapedSymbol)\\s*[:{<]?", options: []) {
                    patterns.append(("enum", regex))
                }
            }
            if type == "any" || type == "protocol" {
                if let regex = try? NSRegularExpression(pattern: "protocol\\s+\(escapedSymbol)\\s*[:{<]?", options: []) {
                    patterns.append(("protocol", regex))
                }
            }
        }
        
        // JavaScript/TypeScript patterns
        if ["js", "jsx", "ts", "tsx", "mjs"].contains(ext) {
            if type == "any" || type == "function" {
                if let regex = try? NSRegularExpression(pattern: "(function\\s+\(escapedSymbol)|const\\s+\(escapedSymbol)\\s*=\\s*(async\\s+)?\\(|let\\s+\(escapedSymbol)\\s*=\\s*(async\\s+)?\\()", options: []) {
                    patterns.append(("function", regex))
                }
            }
            if type == "any" || type == "class" {
                if let regex = try? NSRegularExpression(pattern: "class\\s+\(escapedSymbol)\\s*[{<]?", options: []) {
                    patterns.append(("class", regex))
                }
            }
            if type == "any" || type == "variable" {
                if let regex = try? NSRegularExpression(pattern: "(const|let|var)\\s+\(escapedSymbol)\\s*=", options: []) {
                    patterns.append(("variable", regex))
                }
            }
        }
        
        // Python patterns
        if ext == "py" {
            if type == "any" || type == "function" {
                if let regex = try? NSRegularExpression(pattern: "def\\s+\(escapedSymbol)\\s*\\(", options: []) {
                    patterns.append(("function", regex))
                }
            }
            if type == "any" || type == "class" {
                if let regex = try? NSRegularExpression(pattern: "class\\s+\(escapedSymbol)\\s*[:(]?", options: []) {
                    patterns.append(("class", regex))
                }
            }
        }
        
        // Generic fallback - just look for the symbol as a word
        if patterns.isEmpty {
            if let regex = try? NSRegularExpression(pattern: "\\b\(escapedSymbol)\\b", options: []) {
                patterns.append(("reference", regex))
            }
        }
        
        return patterns
    }
    
    // MARK: - Helper Methods
    
    private func parseGlobPattern(_ pattern: String?) -> [String] {
        guard let pattern = pattern, !pattern.isEmpty else { return [] }
        return pattern.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    private func matchesAnyPattern(_ filename: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if matchesGlob(filename, pattern: pattern) {
                return true
            }
        }
        return false
    }
    
    private func matchesGlob(_ filename: String, pattern: String) -> Bool {
        // If pattern contains wildcards, use glob matching
        if pattern.contains("*") || pattern.contains("?") {
            let regexPattern = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
                .replacingOccurrences(of: "?", with: ".")
            
            if let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: [.caseInsensitive]) {
                let range = NSRange(filename.startIndex..., in: filename)
                return regex.firstMatch(in: filename, range: range) != nil
            }
        }
        
        // Otherwise, use case-insensitive contains matching
        // This allows "minimax-test" to match "minimax-test-project" or "my-minimax-test"
        return filename.lowercased().contains(pattern.lowercased())
    }
    
    private func makeRelativePath(_ path: String) -> String {
        guard let projectPath = projectPath else { return path }
        if path.hasPrefix(projectPath) {
            var relative = String(path.dropFirst(projectPath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative.isEmpty ? "." : relative
        }
        return path
    }
}

// MARK: - Search Result Types

struct SearchMatch {
    let filePath: String
    let lineNumber: Int
    let lineContent: String
}

struct SymbolMatch {
    let filePath: String
    let lineNumber: Int
    let lineContent: String
    let symbolName: String
    let symbolType: String
}

