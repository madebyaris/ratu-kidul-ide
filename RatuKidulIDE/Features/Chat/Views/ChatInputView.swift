import SwiftUI
import SwiftData

struct ChatInputView: View {
    @Binding var text: String
    @Binding var attachments: [Attachment]
    @Binding var selectedModels: [ModelConfig]
    var isLoading: Bool
    var contextUsage: ContextUsage?  // NEW: Real context usage from ViewModel
    var onSend: () -> Void
    
    @Query(sort: \ModelConfig.displayName) private var availableModels: [ModelConfig]
    @State private var showContextDetails = false
    @State private var hasAutoSelectedDefault = false
    @FocusState private var isFocused: Bool
    
    // Use stored context window from model config
    private var contextLimit: Int {
        selectedModels.first?.effectiveContextWindow ?? 128000
    }
    
    // Context display using real usage if available
    private var contextDisplay: String {
        if let usage = contextUsage {
            return usage.displayString
        }
        // Fallback to simple estimate
        let used = text.count / 4
        return "\(formatTokens(used))/\(formatTokens(contextLimit))"
    }
    
    // Context color based on usage percentage
    private var contextColor: Color {
        guard let usage = contextUsage else { return .secondary }
        if usage.percentage >= 0.95 { return .red }
        if usage.percentage >= 0.80 { return .orange }
        if usage.percentage >= 0.60 { return .yellow }
        return .secondary
    }
    
    // Context percentage for display
    private var contextPercentage: String {
        guard let usage = contextUsage else { return "" }
        return String(format: "%.0f%%", usage.percentage * 100)
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(count / 1_000_000)M"
        } else if count >= 1_000 {
            let k = Double(count) / 1000.0
            if k >= 100 {
                return "\(Int(k))K"
            }
            return String(format: "%.1fK", k)
        }
        return "\(count)"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar: Model selector + Context indicator
            HStack(spacing: 12) {
                // Model picker (Menu is much lighter than Popover on macOS)
                Menu {
                    if availableModels.isEmpty {
                        Text("No models configured")
                        Divider()
                        Text("Add models in Settings")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableModels) { model in
                            Button {
                                // Single selection
                                selectedModels = [model]
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                        Text(model.modelId)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedModels.contains(where: { $0.id == model.id }) {
                                        Image(systemName: "checkmark")
                                    }
                                    if model.isDefault {
                                        Text("Default")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cube")
                            .font(.caption)
                        Text(selectedModels.first?.displayName ?? "Select Model")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
                
                // Enhanced Context indicator
                Button(action: { showContextDetails.toggle() }) {
                    HStack(spacing: 6) {
                        // Progress ring
                        if let usage = contextUsage {
                            ContextProgressRing(percentage: usage.percentage, color: contextColor)
                                .frame(width: 16, height: 16)
                        }
                        
                        Text(contextDisplay)
                            .font(.caption)
                            .foregroundStyle(contextColor)
                        
                        if !contextPercentage.isEmpty {
                            Text("(\(contextPercentage))")
                                .font(.caption2)
                                .foregroundStyle(contextColor.opacity(0.8))
                        }
                        
                        // Warning icon when near limit
                        if let usage = contextUsage, usage.isWarning {
                            Image(systemName: usage.isNearLimit ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(contextColor)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(contextColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Context window usage - Click for details")
                .popover(isPresented: $showContextDetails) {
                    ContextDetailsPopover(usage: contextUsage)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Input area
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Type your message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .lineLimit(1...10)
                    .focused($isFocused)
                    .onSubmit {
                        if !text.isEmpty && !isLoading {
                            onSend()
                        }
                    }
                
                VStack(spacing: 4) {
                    Button(action: {
                        if !text.isEmpty && !isLoading {
                            onSend()
                        }
                    }) {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.accentColor)
                            }
                        }
                        .frame(minWidth: 28, maxWidth: 28, minHeight: 28, maxHeight: 28)
                    }
                    .buttonStyle(.borderless)
                    .disabled(text.isEmpty || isLoading)
                    .help("Send (Enter)")
                }
            }
            .padding(12)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            autoSelectDefaultModel()
        }
        .onChange(of: availableModels) { _, _ in
            // Re-check default model when available models change
            if selectedModels.isEmpty {
                autoSelectDefaultModel()
            }
        }
    }
    
    private func autoSelectDefaultModel() {
        // Only auto-select once per view lifecycle
        guard !hasAutoSelectedDefault, selectedModels.isEmpty else { return }
        
        // Find the default model
        if let defaultModel = availableModels.first(where: { $0.isDefault }) {
            selectedModels = [defaultModel]
            hasAutoSelectedDefault = true
        } else if let firstModel = availableModels.first {
            // If no default model, use the first available model
            selectedModels = [firstModel]
            hasAutoSelectedDefault = true
        }
    }
}

// MARK: - Context Progress Ring

struct ContextProgressRing: View {
    let percentage: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
            
            Circle()
                .trim(from: 0, to: min(percentage, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Context Details Popover

struct ContextDetailsPopover: View {
    let usage: ContextUsage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context Window Usage")
                .font(.headline)
            
            if let usage = usage {
                // Progress bar
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor(for: usage.percentage))
                                .frame(width: geo.size.width * min(usage.percentage, 1.0))
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text(usage.displayStringWithPercentage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(usage.remainingTokens) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // Breakdown
                VStack(alignment: .leading, spacing: 6) {
                    Text("Breakdown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    BreakdownRow(label: "System Prompt", tokens: usage.breakdown.systemPrompt)
                    BreakdownRow(label: "Context Summary", tokens: usage.breakdown.contextSummary)
                    BreakdownRow(label: "Previous Messages", tokens: usage.breakdown.previousMessages)
                    BreakdownRow(label: "Current Input", tokens: usage.breakdown.currentInput)
                    BreakdownRow(label: "Attachments", tokens: usage.breakdown.attachments)
                }
                
                // Warning message
                if usage.isNearLimit {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Context nearly full. Auto-summarization will trigger.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if usage.isWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Context window filling up.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                Text("No context data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 300)
    }
    
    private func progressColor(for percentage: Double) -> Color {
        if percentage >= 0.95 { return .red }
        if percentage >= 0.80 { return .orange }
        if percentage >= 0.60 { return .yellow }
        return .accentColor
    }
}

struct BreakdownRow: View {
    let label: String
    let tokens: Int
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(tokens)")
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

