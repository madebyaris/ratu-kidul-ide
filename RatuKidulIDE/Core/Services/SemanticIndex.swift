import Foundation
import NaturalLanguage

// Resolve Range type conflict with LSPTypes.Range
private typealias StringRange = Swift.Range<String.Index>

// MARK: - Semantic Index

/// Provides semantic (meaning-based) search capabilities for code
/// Uses Apple's NaturalLanguage framework for local embeddings
actor SemanticIndex {
    static let shared = SemanticIndex()
    
    /// The project path being indexed
    var projectPath: String?
    
    /// Indexed code chunks
    private var chunks: [CodeChunk] = []
    
    /// Whether the index is currently being built
    private var isIndexing = false
    
    /// Last indexing time
    private var lastIndexTime: Date?
    
    /// File extensions to index
    private let indexableExtensions = Set([
        "swift", "m", "h", "mm", "c", "cpp", "hpp",
        "js", "jsx", "ts", "tsx", "mjs", "cjs",
        "py", "rb", "go", "rs", "java", "kt", "scala",
        "php", "cs", "fs", "vb",
        "html", "htm", "css", "scss", "sass",
        "json", "yaml", "yml", "toml",
        "md", "txt", "sh"
    ])
    
    /// Directories to skip
    private let skipDirectories = Set([
        "node_modules", ".git", ".build", "Pods", "DerivedData",
        ".swiftpm", "__pycache__", "venv", ".venv", ".idea",
        ".vs", "bin", "obj", "target", "dist", "build"
    ])
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Indexing
    
    /// Build or rebuild the semantic index for the project
    func buildIndex(for projectPath: String) async {
        guard !isIndexing else { return }
        
        isIndexing = true
        self.projectPath = projectPath
        chunks = []
        
        await indexDirectory(at: projectPath)
        
        lastIndexTime = Date()
        isIndexing = false
        
        print("SemanticIndex: Indexed \(chunks.count) chunks from \(projectPath)")
    }
    
    /// Update index for a single file (on save)
    func updateFile(at path: String) async {
        guard let projectPath = projectPath else { return }
        
        // Remove existing chunks for this file
        chunks.removeAll { $0.filePath == path }
        
        // Re-index the file
        await indexFile(at: path, relativeTo: projectPath)
    }
    
    /// Remove a file from the index
    func removeFile(at path: String) {
        chunks.removeAll { $0.filePath == path }
    }
    
    private func indexDirectory(at path: String) async {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return }
        
        for item in contents {
            if item.hasPrefix(".") { continue }
            
            let itemPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
            
            if isDir.boolValue {
                if skipDirectories.contains(item) { continue }
                await indexDirectory(at: itemPath)
            } else {
                let ext = (item as NSString).pathExtension.lowercased()
                if indexableExtensions.contains(ext) {
                    await indexFile(at: itemPath, relativeTo: projectPath ?? path)
                }
            }
        }
    }
    
    private func indexFile(at path: String, relativeTo basePath: String) async {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        let chunkSize = 100 // Lines per chunk
        let overlap = 20 // Overlap between chunks
        
        var startLine = 0
        while startLine < lines.count {
            let endLine = min(startLine + chunkSize, lines.count)
            let chunkLines = Array(lines[startLine..<endLine])
            let chunkContent = chunkLines.joined(separator: "\n")
            
            // Extract symbols from the chunk
            let symbols = extractSymbols(from: chunkContent, fileExtension: (path as NSString).pathExtension)
            
            // Generate embedding using NaturalLanguage
            let embedding = generateEmbedding(for: chunkContent)
            
            let chunk = CodeChunk(
                id: UUID().uuidString,
                filePath: path,
                startLine: startLine + 1,
                endLine: endLine,
                content: chunkContent,
                embedding: embedding,
                symbols: symbols
            )
            
            chunks.append(chunk)
            
            startLine += chunkSize - overlap
        }
    }
    
    // MARK: - Search
    
    /// Search for code chunks semantically similar to the query
    func search(query: String, limit: Int = 10) async -> [SemanticSearchResult] {
        guard !chunks.isEmpty else {
            return []
        }
        
        let queryEmbedding = generateEmbedding(for: query)
        
        // Calculate similarity scores
        var results: [(chunk: CodeChunk, score: Float)] = []
        
        for chunk in chunks {
            let similarity = cosineSimilarity(queryEmbedding, chunk.embedding)
            
            // Also boost score if query terms appear in symbols
            let symbolBoost = calculateSymbolBoost(query: query, symbols: chunk.symbols)
            let finalScore = similarity + symbolBoost
            
            results.append((chunk, finalScore))
        }
        
        // Sort by score and take top results
        results.sort { $0.score > $1.score }
        let topResults = results.prefix(limit)
        
        return topResults.map { result in
            SemanticSearchResult(
                chunk: result.chunk,
                score: result.score,
                relativePath: makeRelativePath(result.chunk.filePath)
            )
        }
    }
    
    // MARK: - Embedding Generation
    
    private func generateEmbedding(for text: String) -> [Float] {
        // Use NaturalLanguage framework for sentence embedding
        // This provides a basic semantic representation
        
        if #available(macOS 11.0, *) {
            if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
                // Get embedding for the text (truncated if too long)
                let truncatedText = String(text.prefix(1000))
                if let vector = embedding.vector(for: truncatedText) {
                    return vector.map { Float($0) }
                }
            }
        }
        
        // Fallback: Use word-based approach
        return generateFallbackEmbedding(for: text)
    }
    
    private func generateFallbackEmbedding(for text: String) -> [Float] {
        // Simple TF-IDF-like embedding as fallback
        // Tokenize and create a bag-of-words representation
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text.lowercased()
        
        var wordCounts: [String: Int] = [:]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            let word = String(text[range]).lowercased()
            if word.count > 2 { // Skip very short words
                wordCounts[word, default: 0] += 1
            }
            return true
        }
        
        // Create a simple hash-based embedding
        var embedding = [Float](repeating: 0, count: 256)
        
        for (word, count) in wordCounts {
            let hash = abs(word.hashValue) % 256
            embedding[hash] += Float(count)
        }
        
        // Normalize
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }
        
        return embedding
    }
    
    // MARK: - Similarity Calculation
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }
        
        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        return magnitude > 0 ? dotProduct / magnitude : 0
    }
    
    private func calculateSymbolBoost(query: String, symbols: [String]) -> Float {
        let queryLower = query.lowercased()
        let queryWords = queryLower.components(separatedBy: .whitespaces)
        
        var boost: Float = 0
        
        for symbol in symbols {
            let symbolLower = symbol.lowercased()
            
            // Exact match
            if queryLower.contains(symbolLower) || symbolLower.contains(queryLower) {
                boost += 0.3
            }
            
            // Word match
            for word in queryWords where word.count > 2 {
                if symbolLower.contains(word) {
                    boost += 0.1
                }
            }
        }
        
        return min(boost, 0.5) // Cap the boost
    }
    
    // MARK: - Symbol Extraction
    
    private func extractSymbols(from content: String, fileExtension: String) -> [String] {
        var symbols: [String] = []
        let ext = fileExtension.lowercased()
        
        let patterns: [(String, String)] // (pattern, group)
        
        switch ext {
        case "swift":
            patterns = [
                ("func\\s+(\\w+)", "function"),
                ("class\\s+(\\w+)", "class"),
                ("struct\\s+(\\w+)", "struct"),
                ("enum\\s+(\\w+)", "enum"),
                ("protocol\\s+(\\w+)", "protocol"),
                ("let\\s+(\\w+)\\s*:", "variable"),
                ("var\\s+(\\w+)\\s*:", "variable")
            ]
        case "js", "jsx", "ts", "tsx", "mjs":
            patterns = [
                ("function\\s+(\\w+)", "function"),
                ("class\\s+(\\w+)", "class"),
                ("const\\s+(\\w+)\\s*=", "variable"),
                ("let\\s+(\\w+)\\s*=", "variable"),
                ("(\\w+)\\s*:\\s*function", "method")
            ]
        case "py":
            patterns = [
                ("def\\s+(\\w+)", "function"),
                ("class\\s+(\\w+)", "class")
            ]
        default:
            patterns = [
                ("function\\s+(\\w+)", "function"),
                ("class\\s+(\\w+)", "class"),
                ("def\\s+(\\w+)", "function")
            ]
        }
        
        for (pattern, _) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, range: range)
                
                for match in matches {
                    if match.numberOfRanges > 1,
                       let symbolRange = StringRange(match.range(at: 1), in: content) {
                        let symbol = String(content[symbolRange])
                        if !symbols.contains(symbol) {
                            symbols.append(symbol)
                        }
                    }
                }
            }
        }
        
        return symbols
    }
    
    // MARK: - Helpers
    
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
    
    // MARK: - Index Statistics
    
    var indexStats: IndexStatistics {
        IndexStatistics(
            totalChunks: chunks.count,
            totalFiles: Set(chunks.map { $0.filePath }).count,
            lastIndexed: lastIndexTime,
            isIndexing: isIndexing
        )
    }
}

// MARK: - Data Types

struct CodeChunk {
    let id: String
    let filePath: String
    let startLine: Int
    let endLine: Int
    let content: String
    let embedding: [Float]
    let symbols: [String]
}

struct SemanticSearchResult {
    let chunk: CodeChunk
    let score: Float
    let relativePath: String
}

struct IndexStatistics {
    let totalChunks: Int
    let totalFiles: Int
    let lastIndexed: Date?
    let isIndexing: Bool
}

// MARK: - Semantic Search Tool

/// Tool definition for semantic search
struct SemanticSearchTool: ToolDefinition {
    let name = "semantic_search"
    let description = "Search for code by meaning, not just text. Use natural language queries like 'authentication logic', 'database connection handling', or 'user validation'. Best for finding code when you don't know exact variable/function names."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "query": ToolProperty(
                    type: "string",
                    description: "Natural language description of what you're looking for"
                ),
                "path": ToolProperty(
                    type: "string",
                    description: "Optional directory to limit search scope"
                ),
                "limit": ToolProperty(
                    type: "integer",
                    description: "Maximum number of results (default: 10)"
                )
            ],
            required: ["query"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "search",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

// MARK: - Semantic Search Execution

extension SearchTools {
    /// Perform semantic search using the SemanticIndex
    func semanticSearch(query: String, path: String? = nil, limit: Int = 10) async -> ToolExecutionResult {
        let index = SemanticIndex.shared
        
        // Check if index exists
        let stats = await index.indexStats
        if stats.totalChunks == 0 {
            // Build index if not exists
            if let projectPath = projectPath {
                await index.buildIndex(for: projectPath)
            } else {
                return ToolExecutionResult(
                    toolName: "semantic_search",
                    success: false,
                    output: "",
                    error: "No project indexed. Please open a project first."
                )
            }
        }
        
        let results = await index.search(query: query, limit: limit)
        
        if results.isEmpty {
            return ToolExecutionResult(
                toolName: "semantic_search",
                success: true,
                output: "No relevant code found for: \(query)",
                metadata: ["query": query, "matches": 0]
            )
        }
        
        var output = "Found \(results.count) relevant code section(s) for '\(query)':\n\n"
        
        for (index, result) in results.enumerated() {
            let score = String(format: "%.2f", result.score)
            output += "[\(index + 1)] 📄 \(result.relativePath) (lines \(result.chunk.startLine)-\(result.chunk.endLine)) [score: \(score)]\n"
            
            if !result.chunk.symbols.isEmpty {
                output += "    Symbols: \(result.chunk.symbols.joined(separator: ", "))\n"
            }
            
            // Show preview (first few lines)
            let previewLines = result.chunk.content.components(separatedBy: .newlines).prefix(5)
            let preview = previewLines.map { "    \($0)" }.joined(separator: "\n")
            output += "\(preview)\n"
            if result.chunk.content.components(separatedBy: .newlines).count > 5 {
                output += "    ...\n"
            }
            output += "\n"
        }
        
        return ToolExecutionResult(
            toolName: "semantic_search",
            success: true,
            output: output,
            metadata: ["query": query, "matches": results.count]
        )
    }
}

