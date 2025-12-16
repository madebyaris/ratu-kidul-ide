import Foundation

// MARK: - Tool Executor

/// Routes tool calls to the appropriate handler and executes them
@MainActor
final class ToolExecutor {
    static let shared = ToolExecutor()
    
    private let fileTools = FileTools.shared
    private let searchTools = SearchTools.shared
    private let terminalTools = TerminalTools.shared
    
    /// Delegate for tool execution events
    weak var delegate: ToolExecutorDelegate?
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Set the project path for all tools
    func setProjectPath(_ path: String) async {
        await fileTools.setProjectPath(path)
        await searchTools.setProjectPath(path)
        await terminalTools.setProjectPath(path)
        
        // Build semantic index for the project
        await SemanticIndex.shared.buildIndex(for: path)
    }
    
    // MARK: - Tool Execution
    
    /// Execute a tool call and return the result
    func execute(toolCall: ToolCall) async -> ToolExecutionResult {
        // Notify delegate that execution is starting
        delegate?.toolExecutor(self, willExecute: toolCall)
        
        // Debug: Log tool call details
        print("🔧 Executing tool: \(toolCall.name)")
        print("   Arguments: \(toolCall.arguments.keys.joined(separator: ", "))")
        for (key, value) in toolCall.arguments {
            print("   - \(key): \(value.value)")
        }
        
        let result: ToolExecutionResult
        
        // Route to appropriate handler based on tool name
        // Handle both namespaced (file_read_file) and non-namespaced (read_file) names
        // Also handle variations like file_read_file, read_file, file.read_file, etc.
        var toolName = toolCall.name
        
        // Normalize tool name: remove dots, handle underscores
        toolName = toolName.replacingOccurrences(of: ".", with: "_")
        
        // If name doesn't match, try stripping namespace prefix
        let normalizedName = toolName.lowercased()
        
        print("   🔍 Normalized tool name: '\(toolName)' (original: '\(toolCall.name)')")
        
        switch toolName {
        // File Tools
        case "file_read_file", "read_file":
            result = await executeReadFile(toolCall)
        case "file_write_file", "write_file":
            result = await executeWriteFile(toolCall)
        case "file_edit_file", "edit_file":
            result = await executeEditFile(toolCall)
        case "file_delete_file", "delete_file":
            result = await executeDeleteFile(toolCall)
        case "file_create_directory", "create_directory":
            result = await executeCreateDirectory(toolCall)
        case "file_list_directory", "list_directory":
            result = await executeListDirectory(toolCall)
        case "file_file_exists", "file_exists":
            result = await executeFileExists(toolCall)
        case "file_move_file", "move_file":
            result = await executeMoveFile(toolCall)
            
        // Search Tools
        case "search_grep_search", "grep_search":
            result = await executeGrepSearch(toolCall)
        case "search_find_files", "find_files":
            result = await executeFindFiles(toolCall)
        case "search_find_symbol", "find_symbol":
            result = await executeFindSymbol(toolCall)
        case "search_semantic_search", "semantic_search":
            result = await executeSemanticSearch(toolCall)
            
        // Terminal Tools
        case "terminal_run_command", "run_command":
            result = await executeRunCommand(toolCall)
        case "terminal_run_background", "run_background":
            result = await executeRunBackground(toolCall)
        case "terminal_kill_process", "kill_process":
            result = await executeKillProcess(toolCall)
            
        default:
            result = ToolExecutionResult(
                toolName: toolCall.name,
                success: false,
                output: "",
                error: "Unknown tool: \(toolCall.name)"
            )
        }
        
        // Notify delegate that execution completed
        delegate?.toolExecutor(self, didExecute: toolCall, result: result)
        
        return result
    }
    
    /// Execute multiple tool calls in sequence
    func executeAll(_ toolCalls: [ToolCall]) async -> [ToolResult] {
        var results: [ToolResult] = []
        
        for toolCall in toolCalls {
            let result = await execute(toolCall: toolCall)
            results.append(result.toToolResult(id: toolCall.id))
        }
        
        return results
    }
    
    // MARK: - File Tool Handlers
    
    private func executeReadFile(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let rawPath = extractStringArg(toolCall.arguments, key: "path"), !rawPath.isEmpty else {
            let providedArgs = toolCall.arguments.keys.joined(separator: ", ")
            return ToolExecutionResult(
                toolName: "read_file",
                success: false,
                output: "",
                error: "Missing required parameter: 'path'. Provided arguments: [\(providedArgs.isEmpty ? "none" : providedArgs)]"
            )
        }

        let path = await normalizeProjectPath(rawPath)
        
        let startLine = extractIntArg(toolCall.arguments, key: "start_line")
        let endLine = extractIntArg(toolCall.arguments, key: "end_line")
        
        // Read the file first
        let readResult = await fileTools.readFile(path: path, startLine: startLine, endLine: endLine)
        
        // If reading full file and it's markdown, enhance with parsing
        if readResult.success && startLine == nil && endLine == nil {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                print("📝 Parsing markdown file: \(path)")
                let parser = await MarkdownParser.shared
                let parsed = await parser.parse(readResult.output)
                print("   Found \(parsed.sections.count) sections, \(parsed.codeBlocks.count) code blocks")
                
                // Append markdown structure summary
                var output = readResult.output
                output += "\n\n---\n"
                output += parsed.summary
                
                return ToolExecutionResult(
                    toolName: "read_file",
                    success: true,
                    output: output,
                    metadata: [
                        "path": path,
                        "is_markdown": true,
                        "sections": parsed.sections.count,
                        "code_blocks": parsed.codeBlocks.count,
                        "links": parsed.links.count
                    ]
                )
            }
        }
        
        return readResult
    }

    /// Normalize paths from models that send `/foo/bar` to mean `foo/bar` (project-relative).
    /// Keeps true absolute paths when they're inside the project root.
    private func normalizeProjectPath(_ input: String) async -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return trimmed }

        // If tools are configured, keep absolute paths that are within project root.
        let root = await fileTools.getProjectRoot()
        if let root, !root.isEmpty {
            let normalizedRoot = (root as NSString).standardizingPath
            let normalizedInput = (trimmed as NSString).standardizingPath
            if normalizedInput.hasPrefix(normalizedRoot) {
                return trimmed
            }
        }

        // Otherwise treat `/x/y` as project-relative `x/y`
        return String(trimmed.dropFirst())
    }
    
    private func executeWriteFile(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let rawPath = extractStringArg(toolCall.arguments, key: "path"), !rawPath.isEmpty else {
            return ToolExecutionResult(
                toolName: "write_file",
                success: false,
                output: "",
                error: "Missing required parameter: path"
            )
        }
        
        guard let content = extractStringArg(toolCall.arguments, key: "content") else {
            return ToolExecutionResult(
                toolName: "write_file",
                success: false,
                output: "",
                error: "Missing required parameter: content"
            )
        }
        
        let path = await normalizeProjectPath(rawPath)
        return await fileTools.writeFile(path: path, content: content)
    }
    
    private func executeEditFile(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let rawPath = extractStringArg(toolCall.arguments, key: "path"), !rawPath.isEmpty else {
            return ToolExecutionResult(
                toolName: "edit_file",
                success: false,
                output: "",
                error: "Missing required parameter: path"
            )
        }
        
        guard let oldText = extractStringArg(toolCall.arguments, key: "old_text") else {
            return ToolExecutionResult(
                toolName: "edit_file",
                success: false,
                output: "",
                error: "Missing required parameter: old_text"
            )
        }
        
        guard let newText = extractStringArg(toolCall.arguments, key: "new_text") else {
            return ToolExecutionResult(
                toolName: "edit_file",
                success: false,
                output: "",
                error: "Missing required parameter: new_text"
            )
        }
        
        let path = await normalizeProjectPath(rawPath)
        return await fileTools.editFile(path: path, oldText: oldText, newText: newText)
    }
    
    private func executeDeleteFile(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let rawPath = extractStringArg(toolCall.arguments, key: "path"), !rawPath.isEmpty else {
            return ToolExecutionResult(
                toolName: "delete_file",
                success: false,
                output: "",
                error: "Missing required parameter: path"
            )
        }

        let path = await normalizeProjectPath(rawPath)
        return await fileTools.deleteFile(path: path)
    }
    
    private func executeCreateDirectory(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let rawPath = extractStringArg(toolCall.arguments, key: "path"), !rawPath.isEmpty else {
            return ToolExecutionResult(
                toolName: "create_directory",
                success: false,
                output: "",
                error: "Missing required parameter: path"
            )
        }

        let path = await normalizeProjectPath(rawPath)
        return await fileTools.createDirectory(path: path)
    }
    
    private func executeListDirectory(_ toolCall: ToolCall) async -> ToolExecutionResult {
        // Path defaults to "." (project root) if not provided
        let rawPath = extractStringArg(toolCall.arguments, key: "path") ?? "."
        let path = await normalizeProjectPath(rawPath)
        
        guard !path.isEmpty else {
            return ToolExecutionResult(
                toolName: "list_directory",
                success: false,
                output: "",
                error: "Path cannot be empty"
            )
        }
        
        let recursive = extractBoolArg(toolCall.arguments, key: "recursive") ?? false
        let maxDepth = extractIntArg(toolCall.arguments, key: "max_depth") ?? 3
        
        return await fileTools.listDirectory(path: path, recursive: recursive, maxDepth: maxDepth)
    }
    
    private func executeFileExists(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let rawPath = extractStringArg(toolCall.arguments, key: "path"), !rawPath.isEmpty else {
            return ToolExecutionResult(
                toolName: "file_exists",
                success: false,
                output: "",
                error: "Missing required parameter: path"
            )
        }

        let path = await normalizeProjectPath(rawPath)
        return await fileTools.fileExists(path: path)
    }
    
    private func executeMoveFile(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let rawSource = extractStringArg(toolCall.arguments, key: "source"), !rawSource.isEmpty else {
            return ToolExecutionResult(
                toolName: "move_file",
                success: false,
                output: "",
                error: "Missing required parameter: source"
            )
        }
        
        guard let rawDestination = extractStringArg(toolCall.arguments, key: "destination"), !rawDestination.isEmpty else {
            return ToolExecutionResult(
                toolName: "move_file",
                success: false,
                output: "",
                error: "Missing required parameter: destination"
            )
        }

        let source = await normalizeProjectPath(rawSource)
        let destination = await normalizeProjectPath(rawDestination)
        return await fileTools.moveFile(source: source, destination: destination)
    }
    
    // MARK: - Search Tool Handlers
    
    private func executeGrepSearch(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let pattern = extractStringArg(toolCall.arguments, key: "pattern"), !pattern.isEmpty else {
            return ToolExecutionResult(
                toolName: "grep_search",
                success: false,
                output: "",
                error: "Missing required parameter: pattern"
            )
        }
        
        let path = extractStringArg(toolCall.arguments, key: "path")
        let include = extractStringArg(toolCall.arguments, key: "include")
        let exclude = extractStringArg(toolCall.arguments, key: "exclude")
        let caseSensitive = extractBoolArg(toolCall.arguments, key: "case_sensitive") ?? false
        let maxResults = extractIntArg(toolCall.arguments, key: "max_results") ?? 50
        
        return await searchTools.grepSearch(
            pattern: pattern,
            path: path,
            include: include,
            exclude: exclude,
            caseSensitive: caseSensitive,
            maxResults: maxResults
        )
    }
    
    private func executeFindFiles(_ toolCall: ToolCall) async -> ToolExecutionResult {
        // Pattern is optional, default to "*" (all files) if not provided
        let pattern = extractStringArg(toolCall.arguments, key: "pattern") ?? "*"
        
        let path = extractStringArg(toolCall.arguments, key: "path")
        let maxResults = extractIntArg(toolCall.arguments, key: "max_results") ?? 20
        
        return await searchTools.findFiles(pattern: pattern, path: path, maxResults: maxResults)
    }
    
    private func executeFindSymbol(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let symbol = extractStringArg(toolCall.arguments, key: "symbol"), !symbol.isEmpty else {
            return ToolExecutionResult(
                toolName: "find_symbol",
                success: false,
                output: "",
                error: "Missing required parameter: symbol"
            )
        }
        
        let path = extractStringArg(toolCall.arguments, key: "path")
        let type = extractStringArg(toolCall.arguments, key: "type") ?? "any"
        
        return await searchTools.findSymbol(symbol: symbol, path: path, type: type)
    }
    
    private func executeSemanticSearch(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let query = extractStringArg(toolCall.arguments, key: "query"), !query.isEmpty else {
            return ToolExecutionResult(
                toolName: "semantic_search",
                success: false,
                output: "",
                error: "Missing required parameter: query"
            )
        }
        
        let path = extractStringArg(toolCall.arguments, key: "path")
        let limit = extractIntArg(toolCall.arguments, key: "limit") ?? 10
        
        return await searchTools.semanticSearch(query: query, path: path, limit: limit)
    }
    
    // MARK: - Terminal Tool Handlers
    
    private func executeRunCommand(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let command = extractStringArg(toolCall.arguments, key: "command"), !command.isEmpty else {
            return ToolExecutionResult(
                toolName: "run_command",
                success: false,
                output: "",
                error: "Missing required parameter: command"
            )
        }
        
        let cwd = extractStringArg(toolCall.arguments, key: "cwd")
        let timeout = extractIntArg(toolCall.arguments, key: "timeout") ?? 60
        
        return await terminalTools.runCommand(command: command, cwd: cwd, timeout: timeout)
    }
    
    private func executeRunBackground(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let command = extractStringArg(toolCall.arguments, key: "command"), !command.isEmpty else {
            return ToolExecutionResult(
                toolName: "run_background",
                success: false,
                output: "",
                error: "Missing required parameter: command"
            )
        }
        
        let cwd = extractStringArg(toolCall.arguments, key: "cwd")
        
        return await terminalTools.runBackground(command: command, cwd: cwd)
    }
    
    private func executeKillProcess(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let pid = extractIntArg(toolCall.arguments, key: "pid") else {
            return ToolExecutionResult(
                toolName: "kill_process",
                success: false,
                output: "",
                error: "Missing required parameter: pid"
            )
        }
        
        return await terminalTools.killProcess(pid: Int32(pid))
    }
}

// MARK: - Argument Extraction Helpers

extension ToolExecutor {
    private func unwrapAnyCodable(_ value: Any) -> Any {
        var current: Any = value
        // Unwrap nested AnyCodable wrappers (can happen when providers re-wrap existing AnyCodable)
        while let wrapped = current as? AnyCodable {
            current = wrapped.value
        }
        return current
    }

    /// Extract a string argument, handling various formats
    func extractStringArg(_ args: [String: AnyCodable], key: String) -> String? {
        print("   🔍 extractStringArg(\(key)): Looking in \(args.count) arguments")
        print("      Available keys: \(args.keys.joined(separator: ", "))")
        
        guard let value = args[key]?.value else {
            print("      ❌ Key '\(key)' not found")
            return nil
        }
        
        let unwrapped = unwrapAnyCodable(value)
        print("      ✅ Found value: \(unwrapped) (type: \(type(of: unwrapped)))")
        
        if let str = unwrapped as? String {
            print("      ✅ Extracted as String: '\(str)'")
            return str
        }
        // Handle case where value might be wrapped differently
        let stringValue = String(describing: unwrapped)
        print("      ⚠️  Converted to String: '\(stringValue)'")
        return stringValue
    }
    
    /// Extract a boolean argument
    func extractBoolArg(_ args: [String: AnyCodable], key: String) -> Bool? {
        guard let value = args[key]?.value else { return nil }
        let unwrapped = unwrapAnyCodable(value)
        
        if let bool = unwrapped as? Bool {
            return bool
        }
        if let str = unwrapped as? String {
            return str.lowercased() == "true" || str == "1"
        }
        if let num = unwrapped as? Int {
            return num != 0
        }
        return nil
    }
    
    /// Extract an integer argument
    func extractIntArg(_ args: [String: AnyCodable], key: String) -> Int? {
        guard let value = args[key]?.value else { return nil }
        let unwrapped = unwrapAnyCodable(value)
        
        if let int = unwrapped as? Int {
            return int
        }
        if let double = unwrapped as? Double {
            return Int(double)
        }
        if let str = unwrapped as? String {
            return Int(str)
        }
        return nil
    }
}

// MARK: - Tool Executor Delegate

protocol ToolExecutorDelegate: AnyObject {
    func toolExecutor(_ executor: ToolExecutor, willExecute toolCall: ToolCall)
    func toolExecutor(_ executor: ToolExecutor, didExecute toolCall: ToolCall, result: ToolExecutionResult)
}

// MARK: - Default Delegate Implementation

extension ToolExecutorDelegate {
    func toolExecutor(_ executor: ToolExecutor, willExecute toolCall: ToolCall) {}
    func toolExecutor(_ executor: ToolExecutor, didExecute toolCall: ToolCall, result: ToolExecutionResult) {}
}

