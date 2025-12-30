import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case apiKeys
    case models
    case tools
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .apiKeys: return "API Keys"
        case .models: return "Models"
        case .tools: return "Tools & MCP"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gear"
        case .apiKeys: return "key"
        case .models: return "cube"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var selectedTab: SettingsTab = .general
    
    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil // system
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .navigationTitle("Settings")
            .frame(minWidth: 200, idealWidth: 220)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
            }
        } detail: {
            // Content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .apiKeys:
                    APIKeysView()
                case .models:
                    ModelsSettingsView()
                case .tools:
                    ToolsSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .preferredColorScheme(colorScheme)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    
    // Font size settings
    @AppStorage("editorFontSize") private var editorFontSize: Double = FontSettingsDefaults.editorFontSize
    @AppStorage("chatFontSize") private var chatFontSize: Double = FontSettingsDefaults.chatFontSize
    @AppStorage("systemFontSize") private var systemFontSize: Double = FontSettingsDefaults.systemFontSize
    
    // Editor layout settings
    @AppStorage("showMinimap") private var showMinimap: Bool = false
    @AppStorage("wrapText") private var wrapText: Bool = false
    
    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            } header: {
                Text("Appearance")
            }
            
            Section {
                // IDE Editor Font Size
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("IDE Editor")
                        Spacer()
                        Text("\(Int(editorFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack(spacing: 12) {
                        Text("A")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        Slider(
                            value: $editorFontSize,
                            in: FontSettingsDefaults.minFontSize...FontSettingsDefaults.maxFontSize,
                            step: 1
                        )
                        
                        Text("A")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                        
                        Stepper("", value: $editorFontSize, in: FontSettingsDefaults.minFontSize...FontSettingsDefaults.maxFontSize)
                            .labelsHidden()
                    }
                    
                    Text("Font size for the code editor")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                
                // Chat Font Size
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Chat & AI Responses")
                        Spacer()
                        Text("\(Int(chatFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack(spacing: 12) {
                        Text("A")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        Slider(
                            value: $chatFontSize,
                            in: FontSettingsDefaults.minFontSize...FontSettingsDefaults.maxFontSize,
                            step: 1
                        )
                        
                        Text("A")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                        
                        Stepper("", value: $chatFontSize, in: FontSettingsDefaults.minFontSize...FontSettingsDefaults.maxFontSize)
                            .labelsHidden()
                    }
                    
                    Text("Font size for chat messages and AI responses")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                
                // System-wide Font Size
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("System-wide")
                        Spacer()
                        Text("\(Int(systemFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack(spacing: 12) {
                        Text("A")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        Slider(
                            value: $systemFontSize,
                            in: FontSettingsDefaults.minFontSize...FontSettingsDefaults.maxFontSize,
                            step: 1
                        )
                        
                        Text("A")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                        
                        Stepper("", value: $systemFontSize, in: FontSettingsDefaults.minFontSize...FontSettingsDefaults.maxFontSize)
                            .labelsHidden()
                    }
                    
                    Text("Default font size for UI elements")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                
                // Reset button
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        withAnimation {
                            editorFontSize = FontSettingsDefaults.editorFontSize
                            chatFontSize = FontSettingsDefaults.chatFontSize
                            systemFontSize = FontSettingsDefaults.systemFontSize
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Font Size")
            }
            
            Section {
                Toggle("Show Minimap", isOn: $showMinimap)
                    .help("Display a minimap overview of the code on the right side")
                
                Toggle("Wrap Text", isOn: $wrapText)
                    .help("Wrap long lines instead of scrolling horizontally")
            } header: {
                Text("Editor Layout")
            } footer: {
                Text("Configure how code is displayed in the editor")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ToolsSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Tools & MCP")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("MCP toolsets configuration coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
