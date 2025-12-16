import SwiftUI
import SwiftData

enum ModelProvider: String, CaseIterable, Identifiable {
    case openai
    case anthropic
    case google
    case minimax
    case grok
    case openrouter
    case perplexity
    case ollama
    case lmstudio
    case openaiCompatible
    case anthropicCompatible
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        case .minimax: return "MiniMax"
        case .grok: return "Grok (xAI)"
        case .openrouter: return "OpenRouter"
        case .perplexity: return "Perplexity"
        case .ollama: return "Ollama"
        case .lmstudio: return "LM Studio"
        case .openaiCompatible: return "OpenAI Compatible"
        case .anthropicCompatible: return "Anthropic Compatible"
        }
    }
    
    var keychainKey: String {
        switch self {
        case .openai: return "openai_api_key"
        case .anthropic: return "anthropic_api_key"
        case .google: return "google_api_key"
        case .minimax: return "minimax_api_key"
        case .grok: return "grok_api_key"
        case .openrouter: return "openrouter_api_key"
        case .perplexity: return "perplexity_api_key"
        case .ollama: return ""
        case .lmstudio: return ""
        case .openaiCompatible: return "openai_compatible_api_key"
        case .anthropicCompatible: return "anthropic_compatible_api_key"
        }
    }
    
    var modelIdPrefix: String {
        switch self {
        case .openai: return "openai/"
        case .anthropic: return "anthropic/"
        case .google: return "google/"
        case .minimax: return "minimax/"
        case .grok: return "grok/"
        case .openrouter: return "openrouter::"
        case .perplexity: return "perplexity/"
        case .ollama: return "ollama::"
        case .lmstudio: return "lmstudio::"
        case .openaiCompatible: return "openai-compatible/"
        case .anthropicCompatible: return "anthropic-compatible/"
        }
    }
}

struct AddModelForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let model: ModelConfig?
    @Binding var isPresented: Bool
    
    @State private var selectedProvider: ModelProvider = .openai
    @State private var apiKey: String = ""
    @State private var modelId: String = ""
    @State private var displayName: String = ""
    @State private var systemPrompt: String = ""
    @State private var isDefault: Bool = false
    @State private var contextWindowText: String = "128000"
    @State private var customBaseURL: String = ""
    @State private var isLoadingKey = false
    @State private var errorMessage: String?
    
    private let keychain = KeychainService.shared
    
    // Number formatter for context window
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()
    
    init(model: ModelConfig? = nil, isPresented: Binding<Bool>) {
        self.model = model
        self._isPresented = isPresented
        
        if let model = model {
            // Extract provider from modelId
            let providerName = model.modelId.components(separatedBy: "/").first ?? 
                             model.modelId.components(separatedBy: "::").first ?? ""
            let provider = ModelProvider(rawValue: providerName.lowercased()) ?? .openai
            _selectedProvider = State(initialValue: provider)
            
            // Extract model ID without provider prefix
            let fullModelId = model.modelId
            let modelIdWithoutPrefix: String
            if fullModelId.hasPrefix(provider.modelIdPrefix) {
                modelIdWithoutPrefix = String(fullModelId.dropFirst(provider.modelIdPrefix.count))
            } else {
                modelIdWithoutPrefix = fullModelId
            }
            
            _modelId = State(initialValue: modelIdWithoutPrefix)
            _displayName = State(initialValue: model.displayName)
            _systemPrompt = State(initialValue: model.systemPrompt)
            _isDefault = State(initialValue: model.isDefault)
            _contextWindowText = State(initialValue: String(model.effectiveContextWindow))
            _customBaseURL = State(initialValue: model.customBaseURL ?? "")
        }
    }
    
    /// Whether the selected provider supports custom base URL
    private var supportsCustomURL: Bool {
        selectedProvider == .openaiCompatible || selectedProvider == .anthropicCompatible
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(ModelProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: selectedProvider) { _, _ in
                        loadAPIKey()
                        // Update context window default when provider changes
                        if model == nil { // Only auto-update for new models
                            contextWindowText = String(defaultContextWindow)
                        }
                    }
                    
                    if !selectedProvider.keychainKey.isEmpty {
                        HStack {
                            SecureField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Load from Keychain") {
                                loadAPIKey()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isLoadingKey)
                        }
                    }
                } header: {
                    Text("Provider")
                } footer: {
                    if !selectedProvider.keychainKey.isEmpty {
                        Text("API key is stored securely in macOS Keychain")
                    } else {
                        Text("No API key required for local providers")
                    }
                }
                
                // Custom Base URL section for compatible providers
                if supportsCustomURL {
                    Section {
                        TextField(text: $customBaseURL, prompt: Text(placeholderBaseURL)) {
                            Text("API Base URL")
                        }
                        .textFieldStyle(.roundedBorder)
                    } header: {
                        Text("API Endpoint")
                    } footer: {
                        Text("Enter the full base URL for the API (e.g., https://your-server.com/v1). The URL will be used as-is without modification.")
                    }
                }
                
                Section {
                    TextField(text: $modelId, prompt: Text(placeholderModelId)) {
                        Text("Model ID")
                    }
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: modelId) { _, _ in
                        // Update context window based on model ID when it changes
                        if model == nil { // Only auto-update for new models
                            contextWindowText = String(defaultContextWindow)
                        }
                    }
                    
                    TextField(text: $displayName, prompt: Text("e.g., GPT-4 Turbo")) {
                        Text("Display Name")
                    }
                    .textFieldStyle(.roundedBorder)
                    
                    HStack {
                        TextField(text: $contextWindowText, prompt: Text("128000")) {
                            Text("Context Window (tokens)")
                        }
                        .textFieldStyle(.roundedBorder)
                        
                        Text(contextWindowFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                } header: {
                    Text("Model Configuration")
                } footer: {
                    Text("Context window is the maximum number of tokens the model can process. Common values: GPT-4 (128K), Claude-3 (200K), MiniMax/Gemini (1M)")
                }
                
                Section {
                    TextEditor(text: $systemPrompt)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                } header: {
                    Text("System Prompt (Optional)")
                } footer: {
                    Text("Custom system prompt for this model")
                }
                
                Section {
                    Toggle("Set as default model", isOn: $isDefault)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(model == nil ? "Add Model" : "Edit Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveModel()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 600, height: 700)
        .task {
            if model == nil {
                loadAPIKey()
            } else if !selectedProvider.keychainKey.isEmpty {
                loadAPIKey()
            }
        }
    }
    
    private var placeholderModelId: String {
        switch selectedProvider {
        case .openai: return "gpt-4-turbo"
        case .anthropic: return "claude-3-5-sonnet-20241022"
        case .google: return "gemini-pro"
        case .minimax: return "MiniMax-M2"
        case .grok: return "grok-beta"
        case .openrouter: return "meta-llama/llama-3.1-70b-instruct"
        case .perplexity: return "sonar"
        case .ollama: return "llama2"
        case .lmstudio: return "model-name"
        case .openaiCompatible: return "gpt-4-turbo"
        case .anthropicCompatible: return "claude-3-5-sonnet-20241022"
        }
    }
    
    private var placeholderBaseURL: String {
        switch selectedProvider {
        case .openaiCompatible: return "https://api.example.com/v1"
        case .anthropicCompatible: return "https://api.example.com/v1"
        default: return ""
        }
    }
    
    private var defaultContextWindow: Int {
        let lowercaseModelId = modelId.lowercased()
        
        switch selectedProvider {
        case .openai, .openaiCompatible:
            if lowercaseModelId.contains("gpt-4") { return 128000 }
            if lowercaseModelId.contains("gpt-3.5") { return 16000 }
            if lowercaseModelId.contains("o1") || lowercaseModelId.contains("o3") { return 200000 }
            return 128000
        case .anthropic, .anthropicCompatible:
            if lowercaseModelId.contains("claude-3") { return 200000 }
            if lowercaseModelId.contains("claude-2") { return 100000 }
            return 200000
        case .google:
            return 1000000 // Gemini supports 1M tokens
        case .minimax:
            return 1000000 // MiniMax M1/M2 supports 1M tokens
        case .grok:
            return 131072
        case .openrouter:
            return 128000 // Varies by model
        case .perplexity:
            return 128000
        case .ollama, .lmstudio:
            return 8192 // Local models typically have smaller context
        }
    }
    
    private var contextWindowValue: Int {
        Int(contextWindowText.replacingOccurrences(of: ",", with: "")) ?? 128000
    }
    
    private var contextWindowFormatted: String {
        let value = contextWindowValue
        if value >= 1000000 {
            return "\(value / 1000000)M"
        } else if value >= 1000 {
            return "\(value / 1000)K"
        }
        return "\(value)"
    }
    
    private var isValid: Bool {
        !modelId.isEmpty && !displayName.isEmpty && contextWindowValue > 0
    }
    
    private func loadAPIKey() {
        guard !selectedProvider.keychainKey.isEmpty else { return }
        isLoadingKey = true
        Task {
            do {
                let key = try await keychain.get(selectedProvider.keychainKey) ?? ""
                await MainActor.run {
                    apiKey = key
                    isLoadingKey = false
                }
            } catch {
                await MainActor.run {
                    isLoadingKey = false
                }
            }
        }
    }
    
    private func saveModel() {
        errorMessage = nil
        
        // Save API key if provided (synchronously for now, will be async in future)
        if !selectedProvider.keychainKey.isEmpty && !apiKey.isEmpty {
            Task {
                do {
                    try await keychain.set(apiKey, for: selectedProvider.keychainKey)
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to save API key: \(error.localizedDescription)"
                    }
                    return
                }
            }
        }
        
        // Build full model ID with provider prefix
        let fullModelId: String
        if modelId.hasPrefix(selectedProvider.modelIdPrefix) {
            fullModelId = modelId
        } else {
            fullModelId = selectedProvider.modelIdPrefix + modelId
        }
        
        if let existingModel = model {
            // Update existing model
            existingModel.modelId = fullModelId
            existingModel.displayName = displayName
            existingModel.systemPrompt = systemPrompt
            existingModel.isDefault = isDefault
            existingModel.contextWindow = contextWindowValue
            existingModel.customBaseURL = supportsCustomURL && !customBaseURL.isEmpty ? customBaseURL : nil
            
            // If setting as default, unset others
            if isDefault {
                let descriptor = FetchDescriptor<ModelConfig>()
                if let allModels = try? modelContext.fetch(descriptor) {
                    for m in allModels where m.id != existingModel.id {
                        m.isDefault = false
                    }
                }
            }
        } else {
            // Create new model
            let newModel = ModelConfig(
                id: UUID().uuidString,
                displayName: displayName,
                modelId: fullModelId,
                author: .user,
                systemPrompt: systemPrompt,
                isDefault: isDefault,
                contextWindow: contextWindowValue,
                customBaseURL: supportsCustomURL && !customBaseURL.isEmpty ? customBaseURL : nil
            )
            
            // If setting as default, unset others
            if isDefault {
                let descriptor = FetchDescriptor<ModelConfig>()
                if let allModels = try? modelContext.fetch(descriptor) {
                    for m in allModels {
                        m.isDefault = false
                    }
                }
            }
            
            modelContext.insert(newModel)
        }
        
        do {
            try modelContext.save()
            isPresented = false
        } catch {
            errorMessage = "Failed to save model: \(error.localizedDescription)"
        }
    }
}


