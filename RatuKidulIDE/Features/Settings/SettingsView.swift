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
                // Add more general settings here
            } header: {
                Text("General")
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

