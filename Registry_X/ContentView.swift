import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var authService = AuthService()
    @Environment(\.modelContext) private var modelContext
    @StateObject private var educationManager = TapToPayEducationManager.shared
    @State private var showTapToPaySplash = false

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
    }
}
