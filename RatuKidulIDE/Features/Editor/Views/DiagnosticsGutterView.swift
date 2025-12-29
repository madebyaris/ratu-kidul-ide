import SwiftUI

/// View for displaying diagnostics indicators in the gutter
struct DiagnosticsGutterView: View {
    let diagnostics: [Diagnostic]
    let lineNumber: Int
    
    var diagnosticsForLine: [Diagnostic] {
        diagnostics.filter { diag in
            diag.range.start.line <= lineNumber && diag.range.end.line >= lineNumber
        }
    }
    
    var highestSeverity: DiagnosticSeverity? {
        diagnosticsForLine.map { $0.severity ?? .hint }.min(by: { $0.rawValue < $1.rawValue })
    }
    
    var body: some View {
        if let severity = highestSeverity {
            Circle()
                .fill(color(for: severity))
                .frame(width: 8, height: 8)
        } else {
            EmptyView()
        }
    }
    
    private func color(for severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .error:
            return .red
        case .warning:
            return .yellow
        case .information:
            return .blue
        case .hint:
            return .gray
        }
    }
}

/// Tooltip view for diagnostic details
struct DiagnosticTooltipView: View {
    let diagnostic: Diagnostic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(color)
                
                if let source = diagnostic.source {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let code = diagnostic.code {
                    Text(codeString(code))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(diagnostic.message)
                .font(.body)
        }
        .padding(8)
        .frame(maxWidth: 300)
        .background(.regularMaterial)
        .cornerRadius(6)
    }
    
    private var iconName: String {
        switch diagnostic.severity {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .information:
            return "info.circle.fill"
        case .hint:
            return "lightbulb.fill"
        case .none:
            return "circle.fill"
        }
    }
    
    private var color: Color {
        switch diagnostic.severity {
        case .error:
            return .red
        case .warning:
            return .yellow
        case .information:
            return .blue
        case .hint:
            return .gray
        case .none:
            return .secondary
        }
    }
    
    private func codeString(_ code: DiagnosticCode) -> String {
        switch code {
        case .int(let value):
            return String(value)
        case .string(let value):
            return value
        }
    }
}

#Preview {
    HStack {
        DiagnosticsGutterView(
            diagnostics: [
                Diagnostic(
                    range: Range(start: Position(line: 5, character: 0), end: Position(line: 5, character: 10)),
                    severity: .error,
                    message: "Undefined variable 'x'"
                )
            ],
            lineNumber: 5
        )
        Text("Line 5")
    }
    .padding()
}
