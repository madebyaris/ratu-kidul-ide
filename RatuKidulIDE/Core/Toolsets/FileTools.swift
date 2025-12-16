import Foundation

// MARK: - File Tools Implementation

/// Handles all file system operations for the AI agent
actor FileTools {
    static let shared = FileTools()
    
    private let fileManager = FileManager.default
    
    /// The base project path for relative path resolution
    private(set) var projectPath: String?
    
    private init() {}
    
    /// Set the project path
    func setProjectPath(_ path: String) {
        projectPath = path
    }
    
    // MARK: - Path Resolution
    
    /// Resolve a path relative to the project root
    /// Returns nil if path is outside project directory (security check)
    func resolvePath(_ path: String) -> String? {
        // If no project path is set, reject all operations
        guard let projectPath = projectPath else {
            return nil
        }
        
        let normalizedProject = (projectPath as NSString).standardizingPath
        
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
    
    /// Get the project root path (for default operations)
    func getProjectRoot() -> String? {
        return projectPath
    }
    
    /// Check if a path is within the project directory (security check)
    func isPathSafe(_ path: String) -> Bool {
        return resolvePath(path) != nil
    }
    
    // MARK: - Read File
    
    func readFile(path: String, startLine: Int? = nil, endLine: Int? = nil) async -> ToolExecutionResult {
        guard let resolvedPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "read_file",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path)"
            )
        }
        
        guard fileManager.fileExists(atPath: resolvedPath) else {
            return ToolExecutionResult(
                toolName: "read_file",
                success: false,
                output: "",
                error: "File not found: \(path)"
            )
        }
        
        do {
            let content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
            
            // If line range specified, extract those lines
            if startLine != nil || endLine != nil {
                let lines = content.components(separatedBy: .newlines)
                let start = max(0, (startLine ?? 1) - 1)
                let end = min(lines.count, endLine ?? lines.count)
                
                guard start < end else {
                    return ToolExecutionResult(
                        toolName: "read_file",
                        success: false,
                        output: "",
                        error: "Invalid line range: \(startLine ?? 1)-\(endLine ?? lines.count)"
                    )
                }
                
                let selectedLines = Array(lines[start..<end])
                let numberedLines = selectedLines.enumerated().map { index, line in
                    let lineNum = start + index + 1
                    return String(format: "%6d|%@", lineNum, line)
                }
                
                return ToolExecutionResult(
                    toolName: "read_file",
                    success: true,
                    output: numberedLines.joined(separator: "\n"),
                    metadata: [
                        "path": resolvedPath,
                        "start_line": start + 1,
                        "end_line": end,
                        "total_lines": lines.count
                    ]
                )
            }
            
            // Return full content with line numbers for smaller files
            let lines = content.components(separatedBy: .newlines)
            if lines.count <= 500 {
                let numberedLines = lines.enumerated().map { index, line in
                    String(format: "%6d|%@", index + 1, line)
                }
                return ToolExecutionResult(
                    toolName: "read_file",
                    success: true,
                    output: numberedLines.joined(separator: "\n"),
                    metadata: ["path": resolvedPath, "total_lines": lines.count]
                )
            } else {
                // For large files, show first 100 lines with a note
                let firstLines = lines.prefix(100).enumerated().map { index, line in
                    String(format: "%6d|%@", index + 1, line)
                }
                let output = firstLines.joined(separator: "\n") + "\n\n[... File has \(lines.count) lines total. Use start_line and end_line parameters to read specific sections ...]"
                return ToolExecutionResult(
                    toolName: "read_file",
                    success: true,
                    output: output,
                    metadata: ["path": resolvedPath, "total_lines": lines.count, "truncated": true]
                )
            }
        } catch {
            return ToolExecutionResult(
                toolName: "read_file",
                success: false,
                output: "",
                error: "Failed to read file: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Write File
    
    func writeFile(path: String, content: String) async -> ToolExecutionResult {
        guard let resolvedPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "write_file",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path)"
            )
        }
        
        // Create parent directories if needed
        let parentDir = (resolvedPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: parentDir) {
            do {
                try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            } catch {
                return ToolExecutionResult(
                    toolName: "write_file",
                    success: false,
                    output: "",
                    error: "Failed to create parent directory: \(error.localizedDescription)"
                )
            }
        }
        
        let isNewFile = !fileManager.fileExists(atPath: resolvedPath)
        
        do {
            try content.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
            
            let lines = content.components(separatedBy: .newlines).count
            let action = isNewFile ? "Created" : "Wrote"
            
            return ToolExecutionResult(
                toolName: "write_file",
                success: true,
                output: "\(action) \(lines) lines to \(path)",
                metadata: [
                    "path": resolvedPath,
                    "lines": lines,
                    "bytes": content.utf8.count,
                    "created": isNewFile
                ]
            )
        } catch {
            return ToolExecutionResult(
                toolName: "write_file",
                success: false,
                output: "",
                error: "Failed to write file: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Edit File
    
    func editFile(path: String, oldText: String, newText: String) async -> ToolExecutionResult {
        guard let resolvedPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "edit_file",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path)"
            )
        }
        
        guard fileManager.fileExists(atPath: resolvedPath) else {
            return ToolExecutionResult(
                toolName: "edit_file",
                success: false,
                output: "",
                error: "File not found: \(path)"
            )
        }
        
        do {
            var content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
            
            // Check if old text exists
            guard content.contains(oldText) else {
                // Provide helpful error with context
                let preview = String(content.prefix(500))
                return ToolExecutionResult(
                    toolName: "edit_file",
                    success: false,
                    output: "",
                    error: "Could not find the specified text to replace. Make sure the old_text matches exactly, including whitespace and indentation.\n\nFile preview:\n\(preview)..."
                )
            }
            
            // Count occurrences
            let occurrences = content.components(separatedBy: oldText).count - 1
            
            // Replace
            content = content.replacingOccurrences(of: oldText, with: newText)
            
            try content.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
            
            return ToolExecutionResult(
                toolName: "edit_file",
                success: true,
                output: "Successfully replaced \(occurrences) occurrence(s) in \(path)",
                metadata: [
                    "path": resolvedPath,
                    "occurrences": occurrences,
                    "old_length": oldText.count,
                    "new_length": newText.count
                ]
            )
        } catch {
            return ToolExecutionResult(
                toolName: "edit_file",
                success: false,
                output: "",
                error: "Failed to edit file: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Delete File
    
    func deleteFile(path: String) async -> ToolExecutionResult {
        guard let resolvedPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "delete_file",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path)"
            )
        }
        
        guard fileManager.fileExists(atPath: resolvedPath) else {
            return ToolExecutionResult(
                toolName: "delete_file",
                success: false,
                output: "",
                error: "File not found: \(path)"
            )
        }
        
        do {
            try fileManager.removeItem(atPath: resolvedPath)
            return ToolExecutionResult(
                toolName: "delete_file",
                success: true,
                output: "Deleted: \(path)",
                metadata: ["path": resolvedPath]
            )
        } catch {
            return ToolExecutionResult(
                toolName: "delete_file",
                success: false,
                output: "",
                error: "Failed to delete file: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Create Directory
    
    func createDirectory(path: String) async -> ToolExecutionResult {
        guard let resolvedPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "create_directory",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path)"
            )
        }
        
        if fileManager.fileExists(atPath: resolvedPath) {
            return ToolExecutionResult(
                toolName: "create_directory",
                success: true,
                output: "Directory already exists: \(path)",
                metadata: ["path": resolvedPath, "already_existed": true]
            )
        }
        
        do {
            try fileManager.createDirectory(atPath: resolvedPath, withIntermediateDirectories: true)
            return ToolExecutionResult(
                toolName: "create_directory",
                success: true,
                output: "Created directory: \(path)",
                metadata: ["path": resolvedPath]
            )
        } catch {
            return ToolExecutionResult(
                toolName: "create_directory",
                success: false,
                output: "",
                error: "Failed to create directory: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - List Directory
    
    func listDirectory(path: String, recursive: Bool = false, maxDepth: Int = 3) async -> ToolExecutionResult {
        // Default to project root if path is empty or "."
        let pathToUse = (path.isEmpty || path == ".") ? (getProjectRoot() ?? path) : path
        
        guard let resolvedPath = resolvePath(pathToUse) else {
            return ToolExecutionResult(
                toolName: "list_directory",
                success: false,
                output: "",
                error: "Path is outside project directory or project path not set. Path: \(path)"
            )
        }
        
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDir), isDir.boolValue else {
            return ToolExecutionResult(
                toolName: "list_directory",
                success: false,
                output: "",
                error: "Directory not found: \(path)"
            )
        }
        
        do {
            var output = ""
            var fileCount = 0
            var dirCount = 0
            
            if recursive {
                output = try listDirectoryRecursive(at: resolvedPath, depth: 0, maxDepth: maxDepth, fileCount: &fileCount, dirCount: &dirCount)
            } else {
                let contents = try fileManager.contentsOfDirectory(atPath: resolvedPath)
                    .filter { !$0.hasPrefix(".") } // Skip hidden files
                    .sorted()
                
                for item in contents {
                    let itemPath = (resolvedPath as NSString).appendingPathComponent(item)
                    var itemIsDir: ObjCBool = false
                    fileManager.fileExists(atPath: itemPath, isDirectory: &itemIsDir)
                    
                    if itemIsDir.boolValue {
                        output += "📁 \(item)/\n"
                        dirCount += 1
                    } else {
                        output += "📄 \(item)\n"
                        fileCount += 1
                    }
                }
            }
            
            let summary = "\n---\n\(dirCount) directories, \(fileCount) files"
            
            return ToolExecutionResult(
                toolName: "list_directory",
                success: true,
                output: output + summary,
                metadata: [
                    "path": resolvedPath,
                    "directories": dirCount,
                    "files": fileCount,
                    "recursive": recursive
                ]
            )
        } catch {
            return ToolExecutionResult(
                toolName: "list_directory",
                success: false,
                output: "",
                error: "Failed to list directory: \(error.localizedDescription)"
            )
        }
    }
    
    private func listDirectoryRecursive(at path: String, depth: Int, maxDepth: Int, fileCount: inout Int, dirCount: inout Int) throws -> String {
        let indent = String(repeating: "  ", count: depth)
        var output = ""
        
        let contents = try fileManager.contentsOfDirectory(atPath: path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        
        // Skip common non-essential directories
        let skipDirs = Set(["node_modules", ".git", ".build", "Pods", "DerivedData", ".swiftpm", "__pycache__", "venv", ".venv"])
        
        for item in contents {
            let itemPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
            
            if isDir.boolValue {
                if skipDirs.contains(item) {
                    output += "\(indent)📁 \(item)/ (skipped)\n"
                } else {
                    output += "\(indent)📁 \(item)/\n"
                    dirCount += 1
                    
                    if depth < maxDepth {
                        output += try listDirectoryRecursive(at: itemPath, depth: depth + 1, maxDepth: maxDepth, fileCount: &fileCount, dirCount: &dirCount)
                    }
                }
            } else {
                output += "\(indent)📄 \(item)\n"
                fileCount += 1
            }
        }
        
        return output
    }
    
    // MARK: - File Exists
    
    func fileExists(path: String) async -> ToolExecutionResult {
        guard let resolvedPath = resolvePath(path) else {
            return ToolExecutionResult(
                toolName: "file_exists",
                success: true,
                output: "Does not exist (outside project): \(path)",
                metadata: [
                    "path": path,
                    "exists": false,
                    "type": "none",
                    "reason": "outside_project"
                ]
            )
        }
        
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDir)
        
        let type: String
        if !exists {
            type = "none"
        } else if isDir.boolValue {
            type = "directory"
        } else {
            type = "file"
        }
        
        return ToolExecutionResult(
            toolName: "file_exists",
            success: true,
            output: exists ? "Exists (\(type)): \(path)" : "Does not exist: \(path)",
            metadata: [
                "path": resolvedPath,
                "exists": exists,
                "type": type
            ]
        )
    }
    
    // MARK: - Move File
    
    func moveFile(source: String, destination: String) async -> ToolExecutionResult {
        guard let resolvedSource = resolvePath(source) else {
            return ToolExecutionResult(
                toolName: "move_file",
                success: false,
                output: "",
                error: "Source path is outside project directory or project path not set. Path: \(source)"
            )
        }
        
        guard let resolvedDest = resolvePath(destination) else {
            return ToolExecutionResult(
                toolName: "move_file",
                success: false,
                output: "",
                error: "Destination path is outside project directory or project path not set. Path: \(destination)"
            )
        }
        
        guard fileManager.fileExists(atPath: resolvedSource) else {
            return ToolExecutionResult(
                toolName: "move_file",
                success: false,
                output: "",
                error: "Source not found: \(source)"
            )
        }
        
        // Create parent directory for destination if needed
        let destParent = (resolvedDest as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: destParent) {
            do {
                try fileManager.createDirectory(atPath: destParent, withIntermediateDirectories: true)
            } catch {
                return ToolExecutionResult(
                    toolName: "move_file",
                    success: false,
                    output: "",
                    error: "Failed to create destination directory: \(error.localizedDescription)"
                )
            }
        }
        
        do {
            try fileManager.moveItem(atPath: resolvedSource, toPath: resolvedDest)
            return ToolExecutionResult(
                toolName: "move_file",
                success: true,
                output: "Moved: \(source) → \(destination)",
                metadata: [
                    "source": resolvedSource,
                    "destination": resolvedDest
                ]
            )
        } catch {
            return ToolExecutionResult(
                toolName: "move_file",
                success: false,
                output: "",
                error: "Failed to move file: \(error.localizedDescription)"
            )
        }
    }
}

