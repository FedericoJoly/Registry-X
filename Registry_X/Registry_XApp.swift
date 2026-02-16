import SwiftUI
import SwiftData
import StripeTerminal

@main
struct Registry_XApp: App {
    @State private var isSplashScreenActive = true
    @State private var modelContainer: ModelContainer?
    
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
                // Initialize ModelContainer in background during splash
                let container = await createModelContainer()
                
                modelContainer = container
                
                // Wait minimum 2 seconds for splash
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isSplashScreenActive = false
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
