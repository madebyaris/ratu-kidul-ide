import SwiftUI
import SwiftData

struct ModelsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ModelConfig.displayName) private var allModels: [ModelConfig]
    @State private var isShowingAddForm = false
    @State private var editingModel: ModelConfig?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Add button
            HStack {
                Text("AI Models")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    isShowingAddForm = true
                }) {
                    Label("Add Model", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Models list
            if allModels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cube")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No models configured")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Add your first model to get started")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    
                    Button("Add Model") {
                        isShowingAddForm = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedModels.keys.sorted(), id: \.self) { provider in
                            Section {
                                ForEach(groupedModels[provider] ?? []) { model in
                                    ModelRow(
                                        model: model,
                                        onEdit: {
                                            editingModel = model
                                        },
                                        onDelete: {
                                            deleteModel(model)
                                        },
                                        onToggleDefault: {
                                            toggleDefault(model)
                                        }
                                    )
                                }
                            } header: {
                                HStack {
                                    Text(provider)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.controlBackgroundColor))
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddForm) {
            AddModelForm(isPresented: $isShowingAddForm)
        }
        .sheet(item: $editingModel) { model in
            AddModelForm(model: model, isPresented: Binding(
                get: { editingModel != nil },
                set: { if !$0 { editingModel = nil } }
            ))
            .onDisappear {
                editingModel = nil
            }
        }
    }
    
    private var groupedModels: [String: [ModelConfig]] {
        Dictionary(grouping: allModels) { model in
            let providerName = model.modelId.components(separatedBy: "/").first ?? 
                              model.modelId.components(separatedBy: "::").first ?? 
                              "Other"
            return providerName.capitalized
        }
    }
    
    private func deleteModel(_ model: ModelConfig) {
        modelContext.delete(model)
        try? modelContext.save()
    }
    
    private func toggleDefault(_ model: ModelConfig) {
        // Set all models to non-default first
        for m in allModels {
            m.isDefault = false
        }
        // Set selected model as default
        model.isDefault = true
        try? modelContext.save()
    }
}

struct ModelRow: View {
    let model: ModelConfig
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleDefault: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if model.isDefault {
                        Text("Default")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                
                Text(model.modelId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !model.systemPrompt.isEmpty {
                    Text(model.systemPrompt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onToggleDefault) {
                    Image(systemName: model.isDefault ? "star.fill" : "star")
                            .foregroundStyle(model.isDefault ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(model.isDefault ? "Remove as default" : "Set as default")
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.vertical, 2)
    }
}

