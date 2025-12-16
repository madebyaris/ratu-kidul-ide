import SwiftUI

struct APIKeysView: View {
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var googleKey: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    
    private let keychain = KeychainService.shared
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OpenAI")
                            .font(.headline)
                        SecureField(text: $openAIKey, prompt: Text("sk-proj-1234567890abcdef...")) {
                            Text("OpenAI API Key")
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Anthropic")
                            .font(.headline)
                        SecureField(text: $anthropicKey, prompt: Text("sk-ant-api03-1234567890abcdef...")) {
                            Text("Anthropic API Key")
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Google")
                            .font(.headline)
                        SecureField(text: $googleKey, prompt: Text("AIzaSy1234567890abcdef...")) {
                            Text("Google API Key")
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
            } header: {
                Text("Provider API Keys")
            } footer: {
                Text("Your API keys are stored securely in the macOS Keychain. They are never sent to any server except the respective AI providers.")
            }
            
            if let message = saveMessage {
                Section {
                    HStack {
                        Image(systemName: saveMessage?.contains("Error") == true ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(saveMessage?.contains("Error") == true ? .red : .green)
                        Text(message)
                            .foregroundStyle(saveMessage?.contains("Error") == true ? .red : .green)
                    }
                }
            }
            
            Section {
                Button(action: {
                    Task {
                        await saveKeys()
                    }
                }) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isSaving ? "Saving..." : "Save All Keys")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadKeys()
        }
    }
    
    private func loadKeys() async {
        do {
            openAIKey = try await keychain.get("openai_api_key") ?? ""
            anthropicKey = try await keychain.get("anthropic_api_key") ?? ""
            googleKey = try await keychain.get("google_api_key") ?? ""
        } catch {
            print("Error loading keys: \(error)")
        }
    }
    
    private func saveKeys() async {
        isSaving = true
        saveMessage = nil
        
        do {
            if !openAIKey.isEmpty {
                try await keychain.set(openAIKey, for: "openai_api_key")
            }
            if !anthropicKey.isEmpty {
                try await keychain.set(anthropicKey, for: "anthropic_api_key")
            }
            if !googleKey.isEmpty {
                try await keychain.set(googleKey, for: "google_api_key")
            }
            
            saveMessage = "API keys saved successfully"
            
            // Clear message after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            saveMessage = nil
        } catch {
            saveMessage = "Error saving keys: \(error.localizedDescription)"
        }
        
        isSaving = false
    }
}

