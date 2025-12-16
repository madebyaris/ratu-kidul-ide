import SwiftUI

// MARK: - Tool Execution Status View

/// Shows the current tool execution status in the chat
struct ToolExecutionStatusView: View {
    let state: AgentState
    let currentTool: ToolCall?
    
    var body: some View {
        if state.isActive {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.statusMessage)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if let tool = currentTool {
                        Text("Running: \(tool.name)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Tool Result Display View

/// Displays a single tool execution result
struct ToolResultDisplayView: View {
    let record: ToolExecutionRecord
    @State private var isExpanded = false
    
    private var toolIcon: String {
        switch record.toolCall.name {
        case let name where name.contains("read"):
            return "doc.text"
        case let name where name.contains("write"):
            return "doc.badge.plus"
        case let name where name.contains("edit"):
            return "pencil"
        case let name where name.contains("delete"):
            return "trash"
        case let name where name.contains("search"), let name where name.contains("grep"), let name where name.contains("find"):
            return "magnifyingglass"
        case let name where name.contains("directory"), let name where name.contains("list"):
            return "folder"
        case let name where name.contains("command"), let name where name.contains("terminal"):
            return "terminal"
        default:
            return "wrench"
        }
    }
    
    private var statusColor: Color {
        record.result.success ? .green : .red
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: toolIcon)
                        .foregroundStyle(statusColor)
                        .frame(width: 20)
                    
                    Text(record.toolCall.name)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                    
                    Image(systemName: record.result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(statusColor)
                        .font(.caption)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Arguments preview
            if !record.toolCall.arguments.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(record.toolCall.arguments.keys.prefix(3)), id: \.self) { key in
                        if let value = record.toolCall.arguments[key]?.value {
                            Text("\(key):")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(formatValue(value))
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            // Expanded content
            if isExpanded {
                Divider()
                
                // Full arguments
                VStack(alignment: .leading, spacing: 4) {
                    Text("Arguments")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ForEach(Array(record.toolCall.arguments.keys), id: \.self) { key in
                        if let value = record.toolCall.arguments[key]?.value {
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(key):")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(formatValue(value))
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Output
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ScrollView {
                        Text(record.result.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                // Error if present
                if let error = record.result.error {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Error")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                        
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func formatValue(_ value: Any) -> String {
        if let string = value as? String {
            return string.count > 50 ? String(string.prefix(50)) + "..." : string
        }
        return String(describing: value)
    }
}

// MARK: - Tool History View

/// Shows the history of tool executions
struct ToolHistoryView: View {
    let history: [ToolExecutionRecord]
    @State private var showAll = false
    
    private var displayedHistory: [ToolExecutionRecord] {
        showAll ? history : Array(history.suffix(3))
    }
    
    var body: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tool Executions")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if history.count > 3 {
                        Button(showAll ? "Show Less" : "Show All (\(history.count))") {
                            withAnimation {
                                showAll.toggle()
                            }
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                
                ForEach(displayedHistory) { record in
                    ToolResultDisplayView(record: record)
                }
            }
            .padding(12)
            .background(Color(.windowBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Inline Tool Result View

/// Compact inline view for tool results in chat messages
struct InlineToolResultView: View {
    let toolName: String
    let success: Bool
    let output: String
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.fill")
                        .font(.caption2)
                        .foregroundStyle(success ? .green : .red)
                    
                    Text(toolName)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                    
                    Image(systemName: success ? "checkmark" : "xmark")
                        .font(.caption2)
                        .foregroundStyle(success ? .green : .red)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(output)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

// MARK: - Tool Toggle View

/// Toggle for enabling/disabling tools in chat
struct ToolToggleView: View {
    @Binding var toolsEnabled: Bool
    
    var body: some View {
        Toggle(isOn: $toolsEnabled) {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption)
                Text("Tools")
                    .font(.caption)
            }
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(toolsEnabled ? Color.accentColor : Color.secondary)
    }
}

// MARK: - Preview

#Preview("Tool Execution Status") {
    VStack(spacing: 16) {
        ToolExecutionStatusView(
            state: .executingTools,
            currentTool: ToolCall(id: "1", name: "read_file", arguments: ["path": "/test.swift"])
        )
        
        ToolExecutionStatusView(
            state: .running,
            currentTool: nil
        )
    }
    .padding()
}

#Preview("Tool Toggle") {
    ToolToggleView(toolsEnabled: .constant(true))
        .padding()
}

