import Foundation

// MARK: - System Prompt Builder

/// Builds dynamic system prompts for AI interactions with tool support
actor SystemPromptBuilder {
    static let shared = SystemPromptBuilder()
    
    private init() {}
    
    // MARK: - Main System Prompt
    
    /// Generate a complete system prompt for AI coding assistance
    func buildSystemPrompt(
        projectName: String?,
        projectPath: String?,
        toolsEnabled: Bool,
        customInstructions: String? = nil
    ) -> String {
        var sections: [String] = []
        
        // Base identity
        sections.append(buildIdentitySection())
        
        // Tools section
        if toolsEnabled {
            sections.append(buildToolsSection())
            sections.append(buildToolGuidelinesSection())
        }
        
        // Project context
        if projectName != nil || projectPath != nil {
            sections.append(buildProjectContextSection(name: projectName, path: projectPath))
        }
        
        // Response guidelines
        sections.append(buildResponseGuidelinesSection())
        
        // Custom instructions
        if let custom = customInstructions, !custom.isEmpty {
            sections.append(buildCustomInstructionsSection(custom))
        }
        
        return sections.joined(separator: "\n\n")
    }
    
    // MARK: - Section Builders
    
    private func buildIdentitySection() -> String {
        """
        You are an AI coding assistant in Ratu Kidul IDE, a native macOS development environment built with SwiftUI.
        
        Your role is to help developers write, understand, debug, and improve code. You have direct access to the user's codebase through a set of tools that allow you to read, write, search, and execute commands.
        """
    }
    
    private func buildToolsSection() -> String {
        """
        ## Available Tools
        
        You have access to the following tools to interact with the codebase:
        
        ### File Operations
        | Tool | Description |
        |------|-------------|
        | `read_file` | Read file contents. Supports line ranges for large files. |
        | `write_file` | Create new files or completely overwrite existing files. |
        | `edit_file` | Make targeted edits using exact search/replace. Preferred for modifications. |
        | `delete_file` | Delete a file permanently. |
        | `create_directory` | Create a new folder (creates parents if needed). |
        | `list_directory` | List contents of a directory (files and folders). Use this to explore project structure. Path defaults to project root if not specified. |
        | `file_exists` | Check if a file or folder exists. |
        | `move_file` | Move or rename a file or directory. |
        
        ### Search Operations
        | Tool | Description |
        |------|-------------|
        | `grep_search` | Fast text/regex search across files. Best for exact strings. |
        | `find_files` | Find files by name pattern (supports wildcards like *.swift). Pattern is optional - if omitted, lists all files. |
        | `find_symbol` | Find function, class, struct, or other symbol definitions. |
        | `semantic_search` | Search code by meaning using natural language queries. |
        
        ### Terminal Operations
        | Tool | Description |
        |------|-------------|
        | `run_command` | Execute shell commands (build, test, git, etc.). |
        | `run_background` | Start long-running processes (servers, watch mode). |
        | `kill_process` | Stop a background process by PID. |
        """
    }
    
    private func buildToolGuidelinesSection() -> String {
        """
        ## Tool Usage Guidelines
        
        ### IMPORTANT: Tool Call Format
        **When you need to use a tool, use the native function calling API provided by the system.**
        - Do NOT output tool calls as text, XML, or markdown
        - Do NOT write tool names in your response text
        - The system will automatically detect and execute your tool calls when you use the function calling API
        - Simply indicate what you're doing in natural language, and the system will handle the tool execution
        
        ### Before Editing
        1. **Always read first**: Use `read_file` to understand the current code before making changes.
        2. **Search before assuming**: Use search tools to find code locations instead of guessing paths.
        3. **Check existence**: Use `file_exists` before reading files you're unsure about.
        
        ### Making Edits
        1. **Prefer `edit_file`**: For modifications to existing files, use `edit_file` with exact matching text.
        2. **Match exactly**: The `old_text` parameter must match the file content exactly, including all whitespace and indentation.
        3. **Use `write_file` sparingly**: Only for new files or complete rewrites.
        4. **Include context**: When using `edit_file`, include enough surrounding code to make the match unique.
        
        ### Search Strategy
        1. **Use `list_directory`** to explore project structure and see what files/folders exist in a directory. This is the best tool for initial exploration.
        2. **Use `find_files`** when you know part of the filename or want to search by pattern (e.g., "*.swift", "test*"). Pattern is optional - omit it to list all files.
        3. **Use `grep_search`** when you know the exact text or pattern to find within file contents.
        4. **Use `semantic_search`** when looking for functionality by concept (e.g., "authentication logic", "error handling").
        5. **Use `find_symbol`** to locate function or class definitions.
        
        ### Terminal Commands
        1. **Explain first**: Tell the user what command you're about to run and why.
        2. **Use appropriate timeouts**: Set reasonable timeouts for commands that might hang.
        3. **Handle errors**: If a command fails, explain the error and suggest fixes.
        4. **Be careful with destructive commands**: Avoid `rm -rf` and similar dangerous operations.
        
        ### Error Handling
        1. **Don't give up**: If a tool fails, try alternative approaches.
        2. **Explain failures**: Tell the user why something failed and what you'll try instead.
        3. **Verify changes**: After making edits, consider reading the file to verify the change was applied correctly.
        """
    }
    
    private func buildProjectContextSection(name: String?, path: String?) -> String {
        var context = "## Current Project\n\n"
        
        if let name = name {
            context += "- **Name**: \(name)\n"
        }
        
        if let path = path {
            context += "- **Path**: \(path)\n"
        }
        
        context += """
        
        When working in this project:
        - Use relative paths when possible (relative to the project root)
        - Respect the project's coding style and conventions
        - Be aware of the project structure when suggesting file locations
        """
        
        return context
    }
    
    private func buildResponseGuidelinesSection() -> String {
        """
        ## Response Guidelines
        
        ### Communication Style
        - Be concise but thorough
        - Explain your reasoning before taking actions
        - Use code blocks with appropriate language tags
        - Format output for readability
        
        ### When Using Tools
        - Announce what tool you're using and why
        - Show relevant results to the user
        - Summarize findings after searches
        - Confirm successful edits
        
        ### Code Quality
        - Follow the project's existing patterns and conventions
        - Write clean, readable, and maintainable code
        - Include appropriate comments for complex logic
        - Consider edge cases and error handling
        
        ### Safety
        - Never execute destructive commands without clear user intent
        - Don't modify files outside the project directory
        - Warn about potentially dangerous operations
        - Preserve backups when making significant changes
        """
    }
    
    private func buildCustomInstructionsSection(_ instructions: String) -> String {
        """
        ## Custom Instructions
        
        The user has provided the following additional instructions:
        
        \(instructions)
        """
    }
    
    // MARK: - Specialized Prompts
    
    /// Generate a prompt for code review
    func buildCodeReviewPrompt() -> String {
        """
        You are reviewing code for quality, correctness, and best practices.
        
        Focus on:
        - Logic errors and bugs
        - Security vulnerabilities
        - Performance issues
        - Code style and readability
        - Missing error handling
        - Potential edge cases
        
        Provide specific, actionable feedback with code examples where helpful.
        """
    }
    
    /// Generate a prompt for debugging assistance
    func buildDebuggingPrompt() -> String {
        """
        You are helping debug an issue in the codebase.
        
        Approach:
        1. Understand the expected vs actual behavior
        2. Search for relevant code using the search tools
        3. Read the relevant files to understand the logic
        4. Identify potential causes
        5. Suggest fixes with specific code changes
        
        Be systematic and explain your debugging process.
        """
    }
    
    /// Generate a prompt for refactoring
    func buildRefactoringPrompt() -> String {
        """
        You are helping refactor code to improve its quality.
        
        Principles:
        - Make small, incremental changes
        - Preserve existing behavior
        - Improve readability and maintainability
        - Follow SOLID principles where applicable
        - Add or improve tests if possible
        
        Explain the benefits of each refactoring step.
        """
    }
}

// MARK: - System Prompt Templates

enum SystemPromptTemplate: String, CaseIterable {
    case general = "General Assistant"
    case codeReview = "Code Review"
    case debugging = "Debugging"
    case refactoring = "Refactoring"
    case documentation = "Documentation"
    
    var description: String {
        switch self {
        case .general:
            return "General-purpose coding assistant"
        case .codeReview:
            return "Focus on code quality and best practices"
        case .debugging:
            return "Help identify and fix bugs"
        case .refactoring:
            return "Improve code structure and maintainability"
        case .documentation:
            return "Write and improve documentation"
        }
    }
}

