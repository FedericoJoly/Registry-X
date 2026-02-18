import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @State private var authService = AuthService()
    @Environment(\.modelContext) private var modelContext
    @StateObject private var educationManager = TapToPayEducationManager.shared
    @State private var showTapToPaySplash = false
    
    // Global auto-finalise timer — fires every 30s regardless of which screen is active
    private let autoFinaliseTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if authService.isAuthenticated {
                EventListView()
                    .onAppear {
                        // Show Tap to Pay splash after authentication if needed (per user)
                        if let userId = authService.currentUser?.id.uuidString,
                           educationManager.shouldShowSplash(for: userId) {
                            // Delay slightly to let the UI settle
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                showTapToPaySplash = true
                            }
                        }
                        // Check immediately on appear
                        AutoFinaliseService.shared.checkAndFinaliseOverdueEvents(modelContext: modelContext)
                    }
            } else {
                LoginView()
            }
        }
        .environment(authService)
        .fullScreenCover(isPresented: $showTapToPaySplash) {
            if let userId = authService.currentUser?.id.uuidString {
                TapToPaySplashView(userId: userId)
            }
        }
        // Fire every 30 seconds while app is active
        .onReceive(autoFinaliseTimer) { _ in
            guard authService.isAuthenticated else { return }
            AutoFinaliseService.shared.checkAndFinaliseOverdueEvents(modelContext: modelContext)
        }
    }
}
