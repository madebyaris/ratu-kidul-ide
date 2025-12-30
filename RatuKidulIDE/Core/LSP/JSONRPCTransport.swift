import Foundation

/// JSON-RPC message types
enum JSONRPCMessageType: String, Codable {
    case request = "request"
    case response = "response"
    case notification = "notification"
    case error = "error"
}

/// JSON-RPC request message
struct JSONRPCRequest: Codable {
    var jsonrpc: String = "2.0"
    var id: Int
    var method: String
    var params: AnyCodable?
    
    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
}

/// JSON-RPC response message
struct JSONRPCResponse: Codable {
    var jsonrpc: String = "2.0"
    var id: Int
    var result: AnyCodable?
    var error: JSONRPCError?
    
    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }
}

/// JSON-RPC error object
struct JSONRPCError: Codable {
    var code: Int
    var message: String
    var data: AnyCodable?
}

/// JSON-RPC notification message
struct JSONRPCNotification: Codable {
    var jsonrpc: String = "2.0"
    var method: String
    var params: AnyCodable?
    
    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, params
    }
}

/// Handles JSON-RPC communication over stdio with a language server
actor JSONRPCTransport {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    
    private var nextRequestId = 1
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var notificationHandler: ((String, AnyCodable?) -> Void)?
    
    private let logger = LSPLogger.shared
    private let requestTimeout: TimeInterval = 30.0
    
    /// Initialize the transport with a process
    func initialize(process: Process) {
        self.process = process
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        
        // Start reading responses
        Task {
            await readResponses()
        }
        
        // Start reading stderr for error messages
        Task {
            await readStderr()
        }
    }
    
    /// Set handler for notifications from the server
    func setNotificationHandler(_ handler: @escaping (String, AnyCodable?) -> Void) {
        notificationHandler = handler
    }
    
    /// Send a request and wait for response
    func sendRequest(method: String, params: AnyCodable?) async throws -> JSONRPCResponse {
        let id = nextRequestId
        nextRequestId += 1
        
        let request = JSONRPCRequest(id: id, method: method, params: params)
        
        await logger.logRequest(method: method, id: id, params: params?.value as? [String: Any])
        
        let startTime = Date()
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            
            // Set timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(requestTimeout * 1_000_000_000))
                if let continuation = pendingRequests.removeValue(forKey: id) {
                    continuation.resume(throwing: LSPError.requestTimeout(method))
                }
            }
            
            // Send request
            Task {
                do {
                    try await sendMessage(request)
                } catch {
                    pendingRequests.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }
    
    /// Send a notification (no response expected)
    func sendNotification(method: String, params: AnyCodable?) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        await logger.logNotification(method: method, params: params?.value as? [String: Any])
        try await sendMessage(notification)
    }
    
    /// Send a JSON-RPC message
    private func sendMessage<T: Codable>(_ message: T) async throws {
        guard let stdinPipe = stdinPipe else {
            throw LSPError.connectionLost
        }
        
        let encoder = JSONEncoder()
        // Don't use sortedKeys - it can cause issues with some LSP servers
        // encoder.outputFormatting = [.sortedKeys]
        
        do {
            let jsonData = try encoder.encode(message)
            
            // Debug: Print the JSON being sent (first 500 chars)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let preview = String(jsonString.prefix(500))
                print("📤 Sending JSON-RPC: \(preview)\(jsonString.count > 500 ? "..." : "")")
            }
            
            let header = "Content-Length: \(jsonData.count)\r\n\r\n"
            
            guard let headerData = header.data(using: .utf8) else {
                throw LSPError.encodingFailed
            }
            
            let handle = stdinPipe.fileHandleForWriting
            
            // Combine header and body into a single write to avoid partial writes
            var fullMessage = Data()
            fullMessage.append(headerData)
            fullMessage.append(jsonData)
            
            // Use the older, more reliable write API for pipes
            // The newer write(contentsOf:) has issues with pipes on some macOS versions
            handle.write(fullMessage)
            
            print("✅ Successfully wrote \(fullMessage.count) bytes to stdin")
        } catch let error as EncodingError {
            print("❌ JSON Encoding Error: \(error)")
            switch error {
            case .invalidValue(let value, let context):
                print("   Invalid value: \(value)")
                print("   Context: \(context.debugDescription)")
                print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            default:
                print("   Error: \(error.localizedDescription)")
            }
            throw error
        } catch {
            print("❌ Write Error: \(error)")
            throw error
        }
    }
    
    /// Read responses from stdout
    private func readResponses() async {
        guard let stdoutPipe = stdoutPipe else { return }
        
        let handle = stdoutPipe.fileHandleForReading
        var buffer = Data()
        var contentLength: Int?
        var headerBuffer = ""
        
        do {
            for try await chunk in handle.bytes {
                buffer.append(chunk)
                
                // Parse header
                if contentLength == nil {
                    if let headerEnd = buffer.range(of: "\r\n\r\n".data(using: .utf8)!) {
                        let headerData = buffer.prefix(upTo: headerEnd.lowerBound)
                        headerBuffer = String(data: headerData, encoding: .utf8) ?? ""
                        
                        // Extract Content-Length
                        for line in headerBuffer.components(separatedBy: "\r\n") {
                            if line.lowercased().hasPrefix("content-length:") {
                                let lengthString = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                                contentLength = Int(lengthString)
                            }
                        }
                        
                        // Remove header from buffer
                        buffer.removeSubrange(..<headerEnd.upperBound)
                    }
                }
                
                // Parse body
                if let length = contentLength, buffer.count >= length {
                    let messageData = buffer.prefix(length)
                    buffer.removeSubrange(..<length)
                    contentLength = nil
                    
                    await processMessage(messageData)
                }
            }
        } catch {
            // Handle read errors
            await logger.logServerLifecycle(language: "unknown", event: "Read error", details: error.localizedDescription)
        }
    }
    
    /// Read stderr for error messages
    private func readStderr() async {
        guard let stderrPipe = stderrPipe else { return }
        
        let handle = stderrPipe.fileHandleForReading
        
        do {
            for try await line in handle.bytes.lines {
                await logger.logServerLifecycle(language: "unknown", event: "stderr", details: line)
            }
        } catch {
            // Ignore stderr read errors
        }
    }
    
    /// Process a received message
    private func processMessage(_ data: Data) async {
        do {
            let decoder = JSONDecoder()
            
            // Try to decode as response first
            if let response = try? decoder.decode(JSONRPCResponse.self, from: data) {
                await handleResponse(response)
                return
            }
            
            // Try to decode as notification
            if let notification = try? decoder.decode(JSONRPCNotification.self, from: data) {
                await handleNotification(notification)
                return
            }
            
            // Try to decode as request (server-initiated)
            if let request = try? decoder.decode(JSONRPCRequest.self, from: data) {
                await handleServerRequest(request)
                return
            }
            
            await logger.logServerLifecycle(language: "unknown", event: "Unknown message type", details: String(data: data, encoding: .utf8))
        } catch {
            await logger.logError(method: "unknown", id: 0, code: -32700, message: "Parse error: \(error.localizedDescription)")
        }
    }
    
    /// Handle a response
    private func handleResponse(_ response: JSONRPCResponse) async {
        let startTime = Date()
        
        if let error = response.error {
            await logger.logError(method: "unknown", id: response.id, code: error.code, message: error.message)
            
            if let continuation = pendingRequests.removeValue(forKey: response.id) {
                let lspError = LSPError.invalidResponse("Code: \(error.code), Message: \(error.message)")
                continuation.resume(throwing: lspError)
            }
        } else {
            let duration = Date().timeIntervalSince(startTime) * 1000
            await logger.logResponse(method: "response", id: response.id, duration: duration)
            
            if let continuation = pendingRequests.removeValue(forKey: response.id) {
                continuation.resume(returning: response)
            }
        }
    }
    
    /// Handle a notification from the server
    private func handleNotification(_ notification: JSONRPCNotification) async {
        await logger.logNotification(method: notification.method, params: notification.params?.value as? [String: Any])
        notificationHandler?(notification.method, notification.params)
    }
    
    /// Handle a server-initiated request (rare, but possible)
    private func handleServerRequest(_ request: JSONRPCRequest) async {
        // Most LSP servers don't send requests to clients, but handle it just in case
        await logger.logRequest(method: request.method, id: request.id, params: request.params?.value as? [String: Any])
        
        // For now, we'll send an error response indicating we don't support server requests
        let errorResponse = JSONRPCResponse(
            id: request.id,
            result: nil,
            error: JSONRPCError(code: -32601, message: "Method not found", data: nil)
        )
        
        do {
            try await sendMessage(errorResponse)
        } catch {
            await logger.logError(method: request.method, id: request.id, code: -32603, message: "Failed to send error response")
        }
    }
    
    /// Close the transport and cleanup
    func close() {
        process?.terminate()
        process = nil
        
        // Cancel all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: LSPError.connectionLost)
        }
        pendingRequests.removeAll()
        
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }
}
