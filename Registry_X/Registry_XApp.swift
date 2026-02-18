import SwiftUI
import SwiftData
import StripeTerminal

@main
struct Registry_XApp: App {
    @State private var isSplashScreenActive = true
    @State private var modelContainer: ModelContainer?
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isSplashScreenActive {
                    SplashView()
                        .transition(.opacity)
                } else if let container = modelContainer {
                    ContentView()
                        .transition(.opacity)
                        .modelContainer(container)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isSplashScreenActive)
            .task {
                // Request notification permission for auto-finalise
                AutoFinaliseService.shared.requestPermissionIfNeeded()
                
                // Initialize ModelContainer in background during splash
                let container = await createModelContainer()
                modelContainer = container
                
                // Wait minimum 2 seconds for splash
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isSplashScreenActive = false
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Check for overdue events every time app comes to foreground
                if newPhase == .active, let container = modelContainer {
                    AutoFinaliseService.shared.checkAndFinaliseOverdueEvents(
                        modelContext: container.mainContext
                    )
                }
            }
        }
    }
    
    private func createModelContainer() async -> ModelContainer {
        await Task.detached {
            let schema = Schema([
                User.self,
                Event.self,
                Product.self,
                Category.self,
                Transaction.self,
                LineItem.self,
                ExchangeRate.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }.value
    }
}
