import Foundation

// MARK: - Tool Definition Protocol

/// Protocol for all tool definitions
protocol ToolDefinition {
    var name: String { get }
    var description: String { get }
    var parameters: ToolParameters { get }
    
    func toUserTool() -> UserTool
}

// MARK: - Tool Parameters

struct ToolParameters: Codable {
    let type: String
    let properties: [String: ToolProperty]
    let required: [String]
    
    init(properties: [String: ToolProperty], required: [String]) {
        self.type = "object"
        self.properties = properties
        self.required = required
    }
    
    func toDict() -> [String: AnyCodable] {
        var dict: [String: Any] = [
            "type": type,
            "required": required
        ]
        
        var propsDict: [String: Any] = [:]
        for (key, prop) in properties {
            propsDict[key] = prop.toDict()
        }
        dict["properties"] = propsDict
        
        return dict.mapValues { AnyCodable($0) }
    }
}

struct ToolProperty: Codable {
    let type: String
    let description: String
    let enumValues: [String]?
    let items: ToolPropertyItems?
    
    init(type: String, description: String, enumValues: [String]? = nil, items: ToolPropertyItems? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
    }
    
    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "description": description
        ]
        if let enumValues = enumValues {
            dict["enum"] = enumValues
        }
        if let items = items {
            dict["items"] = items.toDict()
        }
        return dict
    }
}

struct ToolPropertyItems: Codable {
    let type: String
    
    func toDict() -> [String: Any] {
        return ["type": type]
    }
}

// MARK: - Tool Registry

/// Registry of all available tools
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()
    
    private var tools: [String: any ToolDefinition] = [:]
    
    private init() {
        registerBuiltInTools()
    }
    
    private func registerBuiltInTools() {
        // File Tools
        register(ReadFileTool())
        register(WriteFileTool())
        register(EditFileTool())
        register(DeleteFileTool())
        register(CreateDirectoryTool())
        register(ListDirectoryTool())
        register(FileExistsTool())
        register(MoveFileTool())
        
        // Search Tools
        register(GrepSearchTool())
        register(FindFilesTool())
        register(FindSymbolTool())
        
        // Terminal Tools
        register(RunCommandTool())
        register(RunBackgroundTool())
    }
    
    func register(_ tool: any ToolDefinition) {
        tools[tool.name] = tool
    }
    
    func getTool(named name: String) -> (any ToolDefinition)? {
        return tools[name]
    }
    
    func getAllTools() -> [UserTool] {
        return tools.values.map { $0.toUserTool() }
    }
    
    func getToolNames() -> [String] {
        return Array(tools.keys).sorted()
    }
}

// MARK: - File Tools

struct ReadFileTool: ToolDefinition {
    let name = "read_file"
    let description = "Read the contents of a file. Use this to understand code before making changes. Supports optional line range for large files."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "path": ToolProperty(
                    type: "string",
                    description: "The path to the file to read, relative to the project root or absolute path"
                ),
                "start_line": ToolProperty(
                    type: "integer",
                    description: "Optional starting line number (1-indexed). If omitted, reads from the beginning."
                ),
                "end_line": ToolProperty(
                    type: "integer",
                    description: "Optional ending line number (1-indexed, inclusive). If omitted, reads to the end."
                )
            ],
            required: ["path"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "file",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

struct WriteFileTool: ToolDefinition {
    let name = "write_file"
    let description = "Create a new file or completely overwrite an existing file with new content. Use edit_file for partial modifications."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "path": ToolProperty(
                    type: "string",
                    description: "The path where the file should be created or overwritten"
                ),
                "content": ToolProperty(
                    type: "string",
                    description: "The complete content to write to the file"
                )
            ],
            required: ["path", "content"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "file",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

struct EditFileTool: ToolDefinition {
    let name = "edit_file"
    let description = "Make targeted edits to a file using search and replace. Preferred over write_file for modifications. The old_text must match exactly."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "path": ToolProperty(
                    type: "string",
                    description: "The path to the file to edit"
                ),
                "old_text": ToolProperty(
                    type: "string",
                    description: "The exact text to find and replace. Must match the file content exactly, including whitespace and indentation."
                ),
                "new_text": ToolProperty(
                    type: "string",
                    description: "The new text to replace the old text with"
                )
            ],
            required: ["path", "old_text", "new_text"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "file",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

struct DeleteFileTool: ToolDefinition {
    let name = "delete_file"
    let description = "Delete a file from the filesystem. This action cannot be undone."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "path": ToolProperty(
                    type: "string",
                    description: "The path to the file to delete"
                )
            ],
            required: ["path"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "file",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

struct CreateDirectoryTool: ToolDefinition {
    let name = "create_directory"
    let description = "Create a new directory (folder). Creates parent directories if they don't exist."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "path": ToolProperty(
                    type: "string",
                    description: "The path where the directory should be created"
                )
            ],
            required: ["path"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "file",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

struct ListDirectoryTool: ToolDefinition {
    let name = "list_directory"
    let description = "List the contents of a directory, showing files and subdirectories."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "path": ToolProperty(
                    type: "string",
                    description: "The path to the directory to list"
                ),
                "recursive": ToolProperty(
                    type: "boolean",
                    description: "If true, list contents recursively (default: false)"
                ),
                "max_depth": ToolProperty(
                    type: "integer",
                    description: "Maximum depth for recursive listing (default: 3)"
                )
            ],
            required: ["path"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "file",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

struct FileExistsTool: ToolDefinition {
    let name = "file_exists"
    let description = "Check if a file or directory exists at the given path."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "path": ToolProperty(
                    type: "string",
                    description: "The path to check"
                )
            ],
            required: ["path"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "file",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

struct MoveFileTool: ToolDefinition {
    let name = "move_file"
    let description = "Move or rename a file or directory."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "source": ToolProperty(
                    type: "string",
                    description: "The current path of the file or directory"
                ),
                "destination": ToolProperty(
                    type: "string",
                    description: "The new path for the file or directory"
                )
            ],
            required: ["source", "destination"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "file",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

// MARK: - Search Tools

struct GrepSearchTool: ToolDefinition {
    let name = "grep_search"
    let description = "Search for text or regex patterns in files. Fast and efficient for finding specific strings or patterns across the codebase."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "pattern": ToolProperty(
                    type: "string",
                    description: "The text or regex pattern to search for"
                ),
                "path": ToolProperty(
                    type: "string",
                    description: "The directory or file to search in (default: project root)"
                ),
                "include": ToolProperty(
                    type: "string",
                    description: "File pattern to include (e.g., '*.swift', '*.ts')"
                ),
                "exclude": ToolProperty(
                    type: "string",
                    description: "File pattern to exclude (e.g., 'node_modules', '.git')"
                ),
                "case_sensitive": ToolProperty(
                    type: "boolean",
                    description: "Whether the search is case-sensitive (default: false)"
                ),
                "max_results": ToolProperty(
                    type: "integer",
                    description: "Maximum number of results to return (default: 50)"
                )
            ],
            required: ["pattern"]
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

struct FindFilesTool: ToolDefinition {
    let name = "find_files"
    let description = "Find files and directories by name pattern. Supports wildcards (*, ?) and partial matching. If no pattern is provided, lists all files. Use this to locate files/directories when you know part of the name (e.g., 'minimax-test' will match 'minimax-test-project' or 'my-minimax-test')."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "pattern": ToolProperty(
                    type: "string",
                    description: "The filename pattern to search for (supports wildcards like *.swift). If omitted, searches for all files (*)."
                ),
                "path": ToolProperty(
                    type: "string",
                    description: "The directory to search in (default: project root)"
                ),
                "max_results": ToolProperty(
                    type: "integer",
                    description: "Maximum number of results to return (default: 20)"
                )
            ],
            required: [] // Pattern is optional, defaults to "*"
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

struct FindSymbolTool: ToolDefinition {
    let name = "find_symbol"
    let description = "Find function, class, struct, or other symbol definitions in the codebase."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "symbol": ToolProperty(
                    type: "string",
                    description: "The symbol name to search for (function, class, struct, etc.)"
                ),
                "path": ToolProperty(
                    type: "string",
                    description: "The directory to search in (default: project root)"
                ),
                "type": ToolProperty(
                    type: "string",
                    description: "Type of symbol to find",
                    enumValues: ["function", "class", "struct", "enum", "protocol", "variable", "any"]
                )
            ],
            required: ["symbol"]
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

// MARK: - Terminal Tools

struct RunCommandTool: ToolDefinition {
    let name = "run_command"
    let description = "Execute a shell command and return the output. Use for running build commands, tests, git operations, etc."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "command": ToolProperty(
                    type: "string",
                    description: "The shell command to execute"
                ),
                "cwd": ToolProperty(
                    type: "string",
                    description: "The working directory for the command (default: project root)"
                ),
                "timeout": ToolProperty(
                    type: "integer",
                    description: "Timeout in seconds (default: 60)"
                )
            ],
            required: ["command"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "terminal",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

struct RunBackgroundTool: ToolDefinition {
    let name = "run_background"
    let description = "Start a long-running process in the background (e.g., dev server, watch mode). Returns a process ID that can be used to stop it later."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "command": ToolProperty(
                    type: "string",
                    description: "The shell command to run in the background"
                ),
                "cwd": ToolProperty(
                    type: "string",
                    description: "The working directory for the command (default: project root)"
                )
            ],
            required: ["command"]
        )
    }
    
    func toUserTool() -> UserTool {
        UserTool(
            id: name,
            toolsetName: "terminal",
            displayName: name,
            description: description,
            inputSchema: parameters.toDict()
        )
    }
}

// MARK: - Tool Result

/// Result of executing a tool
struct ToolExecutionResult {
    let toolName: String
    let success: Bool
    let output: String
    let error: String?
    let metadata: [String: Any]?
    
    init(toolName: String, success: Bool, output: String, error: String? = nil, metadata: [String: Any]? = nil) {
        self.toolName = toolName
        self.success = success
        self.output = output
        self.error = error
        self.metadata = metadata
    }
    
    func toToolResult(id: String) -> ToolResult {
        if success {
            return ToolResult(id: id, content: output)
        } else {
            return ToolResult(id: id, content: "Error: \(error ?? output)")
        }
    }
}

