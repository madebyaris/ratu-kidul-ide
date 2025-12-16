import Foundation
import SwiftData

// MARK: - Agent Controller

/// Controls the agentic loop for AI tool execution
/// Handles the cycle of: User message -> AI response -> Tool calls -> Tool results -> AI response
@MainActor
@Observable
final class AgentController {
    // MARK: - Properties
    
    /// Current state of the agent
    var state: AgentState = .idle
    
    /// Current tool being executed (if any)
    var currentToolCall: ToolCall?
    
    /// History of tool executions in current session
    var toolHistory: [ToolExecutionRecord] = []
    
    /// Maximum number of tool call iterations to prevent infinite loops
    var maxIterations: Int = 20
    
    /// Whether to auto-execute tools or require user confirmation
    var autoExecuteTools: Bool = true
    
    /// Pending tool calls waiting for user approval
    var pendingToolCalls: [ToolCall] = []
    
    // MARK: - Dependencies
    
    private let toolExecutor = ToolExecutor.shared
    private let toolRegistry = ToolRegistry.shared
    private let providerRegistry = ProviderRegistry.shared
    private let keychain = KeychainService.shared
    
    /// Project path for tool execution
    var projectPath: String? {
        didSet {
            if let path = projectPath {
                Task {
                    await toolExecutor.setProjectPath(path)
                }
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Register semantic search tool
        toolRegistry.register(SemanticSearchTool())
        toolRegistry.register(KillProcessTool())
    }
    
    // MARK: - Agent Loop
    
    /// Run the agent loop with a user message
    /// Returns the final AI response after all tool calls are complete
    func run(
        userMessage: String,
        modelConfig: ModelConfig,
        context: [LLMMessage],
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onToolResult: @escaping (ToolExecutionResult) -> Void,
        onComplete: @escaping (String, [ToolCall]?) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        state = .running
        toolHistory = []
        
        var messages = context
        var iteration = 0
        var finalResponse = ""
        var allToolCalls: [ToolCall] = []
        
        // Add user message to context
        messages.append(.user(content: userMessage, attachments: []))
        
        while iteration < maxIterations {
            iteration += 1
            
            // Get AI response with tools
            let tools = toolRegistry.getAllTools()
            
            var responseText = ""
            var toolCalls: [ToolCall] = []
            
            do {
                try await providerRegistry.streamResponse(
                    config: modelConfig,
                    messages: messages,
                    tools: tools,
                    onChunk: { chunk in
                        responseText += chunk
                        onChunk(chunk)
                    },
                    onToolCall: { toolCall in
                        toolCalls.append(toolCall)
                        onToolCall(toolCall)
                    },
                    onComplete: { fullText, calls in
                        responseText = fullText
                        if let calls = calls {
                            toolCalls = calls
                        }
                    },
                    onError: { error in
                        onError(error)
                    }
                )
            } catch {
                state = .error(error.localizedDescription)
                onError(error)
                return
            }
            
            // If no tool calls, we're done
            if toolCalls.isEmpty {
                finalResponse = responseText
                state = .idle
                onComplete(finalResponse, allToolCalls.isEmpty ? nil : allToolCalls)
                return
            }
            
            // Add assistant message with tool calls to context
            messages.append(.assistant(content: responseText, model: modelConfig.modelId, toolCalls: toolCalls))
            allToolCalls.append(contentsOf: toolCalls)
            
            // Execute tool calls
            state = .executingTools
            var toolResults: [ToolResult] = []
            
            for toolCall in toolCalls {
                currentToolCall = toolCall
                
                // Check if auto-execute is enabled
                if !autoExecuteTools {
                    pendingToolCalls.append(toolCall)
                    state = .waitingForApproval
                    // Wait for approval (would need external signal)
                    continue
                }
                
                // Execute the tool
                let result = await toolExecutor.execute(toolCall: toolCall)
                
                // Record execution
                let record = ToolExecutionRecord(
                    toolCall: toolCall,
                    result: result,
                    timestamp: Date()
                )
                toolHistory.append(record)
                
                onToolResult(result)
                toolResults.append(result.toToolResult(id: toolCall.id))
            }
            
            currentToolCall = nil
            
            // Add tool results to context
            if !toolResults.isEmpty {
                messages.append(.toolResults(toolResults))
            }
            
            state = .running
        }
        
        // Max iterations reached
        state = .error("Maximum iterations (\(maxIterations)) reached")
        onError(AgentError.maxIterationsReached)
    }
    
    /// Approve pending tool calls
    func approvePendingTools() async -> [ToolExecutionResult] {
        var results: [ToolExecutionResult] = []
        
        for toolCall in pendingToolCalls {
            let result = await toolExecutor.execute(toolCall: toolCall)
            results.append(result)
            
            let record = ToolExecutionRecord(
                toolCall: toolCall,
                result: result,
                timestamp: Date()
            )
            toolHistory.append(record)
        }
        
        pendingToolCalls = []
        state = .running
        
        return results
    }
    
    /// Reject pending tool calls
    func rejectPendingTools() {
        pendingToolCalls = []
        state = .idle
    }
    
    /// Cancel the current agent run
    func cancel() {
        state = .idle
        currentToolCall = nil
        pendingToolCalls = []
    }
    
    // MARK: - System Prompt Generation
    
    /// Generate a system prompt that includes tool descriptions and project context
    func generateSystemPrompt(projectName: String?, projectPath: String?) -> String {
        var prompt = """
        You are an AI coding assistant in Ratu Kidul IDE, a native macOS development environment.
        
        You have access to tools that allow you to interact with the user's codebase and system.
        
        ## Available Tools
        
        ### File Operations
        - **read_file**: Read file contents. Always read files before editing to understand context.
        - **write_file**: Create new files or completely overwrite existing files.
        - **edit_file**: Make targeted edits using search/replace. Preferred for modifications.
        - **delete_file**: Delete a file (use with caution).
        - **create_directory**: Create a new folder.
        - **list_directory**: List contents of a directory.
        - **file_exists**: Check if a file or folder exists.
        - **move_file**: Move or rename a file.
        
        ### Search Operations
        - **grep_search**: Fast text/regex search across files. Use for finding specific strings.
        - **find_files**: Find files by name pattern (supports wildcards like *.swift).
        - **find_symbol**: Find function, class, or other symbol definitions.
        - **semantic_search**: Search code by meaning/intent. Use natural language queries.
        
        ### Terminal Operations
        - **run_command**: Execute shell commands. Use for builds, tests, git, etc.
        - **run_background**: Start long-running processes (servers, watch mode).
        - **kill_process**: Stop a background process.
        
        ## Guidelines
        
        1. **Always read before editing**: Use read_file to understand code context before making changes.
        
        2. **Use edit_file for modifications**: Prefer edit_file over write_file for existing files. The old_text must match exactly, including whitespace.
        
        3. **Search before assuming**: Use search tools to find code locations instead of guessing paths.
        
        4. **Explain your actions**: Tell the user what you're doing before executing tools.
        
        5. **Handle errors gracefully**: If a tool fails, explain why and suggest alternatives.
        
        6. **Be careful with destructive operations**: Confirm before deleting files or running potentially dangerous commands.
        
        7. **Use semantic search for concepts**: When looking for functionality (like "authentication" or "database queries"), use semantic_search.
        
        8. **Use grep_search for exact matches**: When you know the exact text to find, use grep_search.

        9. **Do not run tools unless asked**: Only call tools when the user explicitly requests file/search/terminal actions (or when required to answer the user’s question). Do NOT explore the project “just to understand it” unless the user asked.

        10. **Do not continue past tool runs unless asked**: After executing tools, stop and wait for the user to explicitly say “continue / proceed / next” before doing more tool calls.
        
        """
        
        // Add project context if available
        if let name = projectName {
            prompt += "\n## Current Project\n\n"
            prompt += "- **Project Name**: \(name)\n"
        }
        
        if let path = projectPath {
            prompt += "- **Project Path**: \(path)\n"
        }
        
        prompt += """
        
        ## Response Format
        
        When you need to use tools, explain your reasoning first, then use the appropriate tool.
        After receiving tool results, interpret them for the user and continue with your task.
        
        Be concise but thorough. Focus on solving the user's problem efficiently.
        """
        
        return prompt
    }
}

// MARK: - Agent State

enum AgentState: Equatable {
    case idle
    case running
    case executingTools
    case waitingForApproval
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .running, .executingTools:
            return true
        default:
            return false
        }
    }
    
    var statusMessage: String {
        switch self {
        case .idle:
            return "Ready"
        case .running:
            return "Thinking..."
        case .executingTools:
            return "Executing tools..."
        case .waitingForApproval:
            return "Waiting for approval..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Agent Error

enum AgentError: Error, LocalizedError {
    case maxIterationsReached
    case toolExecutionFailed(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .maxIterationsReached:
            return "Maximum number of tool iterations reached"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        case .cancelled:
            return "Agent execution was cancelled"
        }
    }
}

// MARK: - Tool Execution Record

struct ToolExecutionRecord: Identifiable {
    let id = UUID()
    let toolCall: ToolCall
    let result: ToolExecutionResult
    let timestamp: Date
    
    var duration: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
}

// MARK: - Simple Agent Run (without streaming)

extension AgentController {
    /// Simple synchronous-style agent run for basic use cases
    func runSimple(
        userMessage: String,
        modelConfig: ModelConfig,
        context: [LLMMessage]
    ) async throws -> (response: String, toolCalls: [ToolCall]?) {
        var finalResponse = ""
        var allToolCalls: [ToolCall]? = nil
        var encounteredError: Error?
        
        await run(
            userMessage: userMessage,
            modelConfig: modelConfig,
            context: context,
            onChunk: { _ in },
            onToolCall: { _ in },
            onToolResult: { _ in },
            onComplete: { response, calls in
                finalResponse = response
                allToolCalls = calls
            },
            onError: { error in
                encounteredError = error
            }
        )
        
        if let error = encounteredError {
            throw error
        }
        
        return (finalResponse, allToolCalls)
    }
}

