import SwiftUI
import SwiftData

struct EmptyStateView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var isShowingProjectPicker = false
    @State private var isShowingNewProjectDialog = false
    @State private var newProjectName = ""
    
    var onProjectSelected: ((String) -> Void)?
    
    init(onProjectSelected: ((String) -> Void)? = nil) {
        self.onProjectSelected = onProjectSelected
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("Open a Project")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Select a project folder to begin, or create a new one")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                if !projects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Projects")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        ForEach(projects.prefix(5)) { project in
                            Button(action: {
                                onProjectSelected?(project.id)
                            }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue)
                                    Text(project.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 400)
                }
                
                Button(action: {
                    isShowingNewProjectDialog = true
                }) {
                    Label("New Project", systemImage: "plus.circle.fill")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    isShowingProjectPicker = true
                }) {
                    Label("Open Existing Folder", systemImage: "folder")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .sheet(isPresented: $isShowingNewProjectDialog) {
            NewProjectDialog(
                projectName: $newProjectName,
                isPresented: $isShowingNewProjectDialog,
                onProjectCreated: onProjectSelected
            )
        }
        .fileImporter(
            isPresented: $isShowingProjectPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleProjectSelection(result: result)
        }
    }
    
    private func handleProjectSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource for sandbox
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // Store bookmark data for persistent access
            if let bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(bookmarkData, forKey: "bookmark_\(url.lastPathComponent)")
            }
            
            // Create project from folder with path
            let projectName = url.lastPathComponent
            let project = Project(name: projectName, path: url.path)
            modelContext.insert(project)
            try? modelContext.save()
            onProjectSelected?(project.id)
        case .failure:
            break
        }
    }
}

struct NewProjectDialog: View {
    @Binding var projectName: String
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    var onProjectCreated: ((String) -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.title2)
                .fontWeight(.semibold)
            
            TextField("Project Name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    createProject()
                }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create") {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func createProject() {
        guard !projectName.isEmpty else { return }
        let project = Project(name: projectName)
        modelContext.insert(project)
        try? modelContext.save()
        isPresented = false
        let projectId = project.id
        projectName = ""
        onProjectCreated?(projectId)
    }
}

