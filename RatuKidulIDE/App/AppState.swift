import SwiftUI
import SwiftData

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    
    @Published var selectedChatId: String?
    @Published var selectedProjectId: String? {
        didSet {
            updateLSPProjectRoot()
        }
    }
    
    private init() {
        let schema = Schema([
            Chat.self,
            Message.self,
            MessageSet.self,
            Project.self,
            ModelConfig.self,
            Attachment.self
        ])
        
        // Get the default database URL
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.ratukidul.ide"
        let dbDirectory = appSupportURL.appendingPathComponent(appBundleID)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        
        let dbURL = dbDirectory.appendingPathComponent("default.store")
        let shmURL = dbDirectory.appendingPathComponent("default.store-shm")
        let walURL = dbDirectory.appendingPathComponent("default.store-wal")
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: dbURL
        )
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = modelContainer.mainContext
        } catch {
            // If we can't load the database, it's likely a schema mismatch
            // Delete the old database files and recreate
            print("⚠️ Failed to load database: \(error)")
            print("⚠️ Attempting to reset database...")
            
            // Delete old database files
            try? fileManager.removeItem(at: dbURL)
            try? fileManager.removeItem(at: shmURL)
            try? fileManager.removeItem(at: walURL)
            
            print("✅ Old database files removed")
            
            // Try again with a fresh database
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                modelContext = modelContainer.mainContext
                print("✅ Database recreated successfully")
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }
        
        // Initialize LSP Manager
        Task {
            await updateLSPProjectRoot()
        }
    }
    
    /// Update LSP project root based on selected project
    private func updateLSPProjectRoot() {
        Task {
            if let projectId = selectedProjectId {
                let descriptor = FetchDescriptor<Project>(
                    predicate: #Predicate { $0.id == projectId }
                )
                
                if let project = try? modelContext.fetch(descriptor).first,
                   let projectPath = project.path {
                    await LSPManager.shared.setProjectRoot(projectPath)
                } else {
                    await LSPManager.shared.setProjectRoot(nil)
                }
            } else {
                await LSPManager.shared.setProjectRoot(nil)
            }
        }
    }
    
    /// Cleanup on app termination
    func shutdown() {
        Task {
            await LSPManager.shared.shutdown()
        }
    }
}

