import Foundation

// MARK: - Terminal Tools Implementation

/// Handles shell command execution for the AI agent
actor TerminalTools {
    static let shared = TerminalTools()
    
    /// The base project path for command execution
    private(set) var projectPath: String?
    
    /// Set the project path
    func setProjectPath(_ path: String) {
        projectPath = path
    }
    
    /// Currently running background processes
    private var backgroundProcesses: [Int32: Process] = [:]
    
    /// Dangerous commands that should be blocked
    private let dangerousPatterns = [
        "rm -rf /",
        "rm -rf /*",
        "sudo rm",
        ":(){:|:&};:",  // Fork bomb
        "mkfs",
        "dd if=/dev/",
        "> /dev/sd",
        "chmod -R 777 /",
        "chown -R",
        "wget.*\\|.*sh",
        "curl.*\\|.*sh"
    ]
    
    /// Commands that require extra caution
    private let cautionPatterns = [
        "rm -rf",
        "rm -r",
        "sudo",
        "chmod",
        "chown"
    ]
    
    private init() {}
    
    // MARK: - Command Validation
    
    func validateCommand(_ command: String) -> CommandValidation {
        let lowercased = command.lowercased()
        
        // Check for dangerous patterns
        for pattern in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                if regex.firstMatch(in: lowercased, range: range) != nil {
                    return .blocked(reason: "This command is blocked for safety: \(pattern)")
                }
            }
        }
        
        // Check for caution patterns
        for pattern in cautionPatterns {
            if lowercased.contains(pattern) {
                return .caution(reason: "This command may be destructive: \(pattern)")
            }
        }
        
        return .allowed
    }
    
    // MARK: - Run Command
    
    func runCommand(
        command: String,
        cwd: String? = nil,
        timeout: Int = 60
    ) async -> ToolExecutionResult {
        // Validate command
        let validation = validateCommand(command)
        switch validation {
        case .blocked(let reason):
            return ToolExecutionResult(
                toolName: "run_command",
                success: false,
                output: "",
                error: reason
            )
        case .caution(let reason):
            // Log warning but continue
            print("TerminalTools Warning: \(reason)")
        case .allowed:
            break
        }
        
        guard let workingDirectory = resolveWorkingDirectory(cwd) else {
            return ToolExecutionResult(
                toolName: "run_command",
                success: false,
                output: "",
                error: "Working directory is outside project directory or project path not set. Path: \(cwd ?? "project root")"
            )
        }

        // Enforce: commands must not reference absolute paths outside the project root
        if let root = projectPath, let pathError = validateCommandPaths(command, projectRoot: root) {
            return ToolExecutionResult(
                toolName: "run_command",
                success: false,
                output: "",
                error: pathError
            )
        }
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Set up environment
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        process.environment = environment
        
        do {
            try process.run()
        } catch {
            return ToolExecutionResult(
                toolName: "run_command",
                success: false,
                output: "",
                error: "Failed to start process: \(error.localizedDescription)"
            )
        }
        
        // Set up timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if process.isRunning {
                process.terminate()
            }
        }
        
        // Wait for completion
        process.waitUntilExit()
        timeoutTask.cancel()
        
        // Read output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        let exitCode = process.terminationStatus
        let success = exitCode == 0
        
        // Format result
        var resultOutput = ""
        
        if !output.isEmpty {
            resultOutput += output
        }
        
        if !errorOutput.isEmpty {
            if !resultOutput.isEmpty {
                resultOutput += "\n"
            }
            resultOutput += "stderr:\n\(errorOutput)"
        }
        
        if resultOutput.isEmpty {
            resultOutput = success ? "Command completed successfully (no output)" : "Command failed with exit code \(exitCode)"
        }
        
        // Truncate very long output
        let maxLength = 10000
        if resultOutput.count > maxLength {
            resultOutput = String(resultOutput.prefix(maxLength)) + "\n\n[Output truncated. Total length: \(resultOutput.count) characters]"
        }
        
        return ToolExecutionResult(
            toolName: "run_command",
            success: success,
            output: resultOutput,
            error: success ? nil : "Exit code: \(exitCode)",
            metadata: [
                "command": command,
                "cwd": workingDirectory,
                "exit_code": Int(exitCode),
                "timed_out": process.terminationReason == .uncaughtSignal
            ]
        )
    }
    
    // MARK: - Run Background Process
    
    func runBackground(command: String, cwd: String? = nil) async -> ToolExecutionResult {
        // Validate command
        let validation = validateCommand(command)
        switch validation {
        case .blocked(let reason):
            return ToolExecutionResult(
                toolName: "run_background",
                success: false,
                output: "",
                error: reason
            )
        case .caution(let reason):
            print("TerminalTools Warning: \(reason)")
        case .allowed:
            break
        }
        
        guard let workingDirectory = resolveWorkingDirectory(cwd) else {
            return ToolExecutionResult(
                toolName: "run_background",
                success: false,
                output: "",
                error: "Working directory is outside project directory or project path not set. Path: \(cwd ?? "project root")"
            )
        }

        // Enforce: commands must not reference absolute paths outside the project root
        if let root = projectPath, let pathError = validateCommandPaths(command, projectRoot: root) {
            return ToolExecutionResult(
                toolName: "run_background",
                success: false,
                output: "",
                error: pathError
            )
        }
        
        let process = Process()
        let outputPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        // Set up environment
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        process.environment = environment
        
        do {
            try process.run()
        } catch {
            return ToolExecutionResult(
                toolName: "run_background",
                success: false,
                output: "",
                error: "Failed to start background process: \(error.localizedDescription)"
            )
        }
        
        let pid = process.processIdentifier
        backgroundProcesses[pid] = process
        
        // Read initial output (wait briefly)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        var initialOutput = ""
        if let data = try? outputPipe.fileHandleForReading.availableData,
           let output = String(data: data, encoding: .utf8) {
            initialOutput = output
        }
        
        var resultOutput = "Started background process with PID: \(pid)\n"
        resultOutput += "Command: \(command)\n"
        resultOutput += "Working directory: \(workingDirectory)\n"
        
        if !initialOutput.isEmpty {
            resultOutput += "\nInitial output:\n\(initialOutput)"
        }
        
        return ToolExecutionResult(
            toolName: "run_background",
            success: true,
            output: resultOutput,
            metadata: [
                "pid": Int(pid),
                "command": command,
                "cwd": workingDirectory
            ]
        )
    }
    
    // MARK: - Kill Process
    
    func killProcess(pid: Int32) async -> ToolExecutionResult {
        if let process = backgroundProcesses[pid] {
            if process.isRunning {
                process.terminate()
                backgroundProcesses.removeValue(forKey: pid)
                return ToolExecutionResult(
                    toolName: "kill_process",
                    success: true,
                    output: "Terminated process with PID: \(pid)",
                    metadata: ["pid": Int(pid)]
                )
            } else {
                backgroundProcesses.removeValue(forKey: pid)
                return ToolExecutionResult(
                    toolName: "kill_process",
                    success: true,
                    output: "Process \(pid) was already terminated",
                    metadata: ["pid": Int(pid), "already_terminated": true]
                )
            }
        }
        
        // Try to kill system-wide process
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
        killProcess.arguments = ["-9", String(pid)]
        
        do {
            try killProcess.run()
            killProcess.waitUntilExit()
            
            let success = killProcess.terminationStatus == 0
            return ToolExecutionResult(
                toolName: "kill_process",
                success: success,
                output: success ? "Killed process \(pid)" : "Failed to kill process \(pid)",
                error: success ? nil : "Process may not exist or permission denied",
                metadata: ["pid": Int(pid)]
            )
        } catch {
            return ToolExecutionResult(
                toolName: "kill_process",
                success: false,
                output: "",
                error: "Failed to kill process: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - List Background Processes
    
    func listBackgroundProcesses() -> [(pid: Int32, isRunning: Bool)] {
        var result: [(Int32, Bool)] = []
        
        for (pid, process) in backgroundProcesses {
            result.append((pid, process.isRunning))
        }
        
        // Clean up terminated processes
        backgroundProcesses = backgroundProcesses.filter { $0.value.isRunning }
        
        return result
    }
    
    // MARK: - Helpers
    
    private func resolveWorkingDirectory(_ cwd: String?) -> String? {
        // Require project path to be set
        guard let projectPath = projectPath else {
            return nil
        }
        
        let normalizedProject = (projectPath as NSString).standardizingPath
        
        // Default to project root if cwd is empty or nil
        guard let cwd = cwd, !cwd.isEmpty, cwd != "." else {
            return normalizedProject
        }
        
        // Handle relative paths
        if !cwd.hasPrefix("/") {
            let resolved = (projectPath as NSString).appendingPathComponent(cwd)
            let normalized = (resolved as NSString).standardizingPath
            // Ensure it's still within project
            if normalized.hasPrefix(normalizedProject) {
                return normalized
            }
            return nil
        }
        
        // Handle absolute paths - only allow if within project directory
        let normalizedPath = (cwd as NSString).standardizingPath
        if normalizedPath.hasPrefix(normalizedProject) {
            return normalizedPath
        }
        
        // Path is outside project directory - reject
        return nil
    }

    /// Blocks commands that include absolute filesystem paths outside the project root.
    /// This prevents models from using `ls /Users/...` etc while still allowing project-relative usage.
    private func validateCommandPaths(_ command: String, projectRoot: String) -> String? {
        let normalizedProject = (projectRoot as NSString).standardizingPath

        // Roughly extract absolute paths like /foo/bar (ignores things like URLs)
        let pattern = #"(?<!:)(/[^ \t\n\r"']+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(command.startIndex..., in: command)
        let matches = regex.matches(in: command, range: range)

        for match in matches {
            guard let r = Range(match.range(at: 1), in: command) else { continue }
            let p = String(command[r])
            let normalized = (p as NSString).standardizingPath
            if !normalized.hasPrefix(normalizedProject) {
                return "Command references path outside project root: \(p). Use relative paths inside the project."
            }
        }

        return nil
    }
}

// MARK: - Command Validation

enum CommandValidation {
    case allowed
    case caution(reason: String)
    case blocked(reason: String)
}

// MARK: - Kill Process Tool Definition

struct KillProcessTool: ToolDefinition {
    let name = "kill_process"
    let description = "Terminate a running background process by its PID."
    
    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "pid": ToolProperty(
                    type: "integer",
                    description: "The process ID to terminate"
                )
            ],
            required: ["pid"]
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

