import Foundation

/// Errors that can occur during LSP operations
enum LSPError: LocalizedError {
    case serverNotFound(String)
    case processLaunchFailed(String, String)
    case requestTimeout(String)
    case serverCrashed(String)
    case invalidResponse(String)
    case encodingFailed
    case decodingFailed(Error)
    case connectionLost
    case initializationFailed(String)
    case unsupportedFeature(String)
    case invalidRequest(String)
    
    var errorDescription: String? {
        switch self {
        case .serverNotFound(let language):
            return "Language server for \(language) not found. Please install it or configure the path in Settings."
        case .processLaunchFailed(let command, let reason):
            return "Failed to launch language server: \(command)\nReason: \(reason)"
        case .requestTimeout(let method):
            return "LSP request '\(method)' timed out. The language server may be unresponsive."
        case .serverCrashed(let language):
            return "Language server for \(language) crashed. It will be restarted automatically."
        case .invalidResponse(let details):
            return "Received invalid response from language server: \(details)"
        case .encodingFailed:
            return "Failed to encode LSP message"
        case .decodingFailed(let error):
            return "Failed to decode LSP response: \(error.localizedDescription)"
        case .connectionLost:
            return "Connection to language server lost"
        case .initializationFailed(let reason):
            return "Failed to initialize language server: \(reason)"
        case .unsupportedFeature(let feature):
            return "Language server does not support feature: \(feature)"
        case .invalidRequest(let details):
            return "Invalid LSP request: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .serverNotFound:
            return "Check Settings > Language Servers to configure the server path"
        case .processLaunchFailed:
            return "Verify the server executable path and permissions"
        case .requestTimeout:
            return "Try again or restart the language server"
        case .serverCrashed:
            return "The server will restart automatically. If problems persist, check the logs."
        default:
            return nil
        }
    }
}
