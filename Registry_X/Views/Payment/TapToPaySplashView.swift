import SwiftUI

/// Full-screen splash modal to introduce Tap to Pay on iPhone
/// Shown once per user after first login
struct TapToPaySplashView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var educationManager = TapToPayEducationManager.shared
    
    let userId: String
    
    @State private var showTerms = false
    @State private var showEducation = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                }
                
                // Title
                Text("Tap to Pay on iPhone")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                
                // Description
                VStack(spacing: 16) {
                    Text("Accept contactless payments right on your iPhone")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("No extra hardware needed")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                
                // Features
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "creditcard.fill",
                        title: "Contactless Cards",
                        description: "Accept all major card brands"
                    )
                    
                    FeatureRow(
                        icon: "applelogo",
                        title: "Apple Pay & Wallets",
                        description: "Accept digital payments instantly"
                    )
                    
                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "Secure & Private",
                        description: "End-to-end encrypted transactions"
                    )
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        // Mark splash as shown and show T&C
                        educationManager.markSplashShown(for: userId)
                        showTerms = true
                    }) {
                        Text("Learn How It Works")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(14)
                    }
                    
                    Button(action: {
                        educationManager.markSplashShown(for: userId)
                        dismiss()
                    }) {
                        Text("Maybe Later")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        // T&C Modal - shown first
        .sheet(isPresented: $showTerms) {
            TapToPayTermsView(userId: userId) {
                // After T&C accepted, dismiss T&C and show education
                showTerms = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showEducation = true
                }
            }
        }
        // Education Modal - shown after T&C
        .sheet(isPresented: $showEducation) {
            // When education is dismissed, also dismiss the splash
            dismiss()
        } content: {
            NavigationView {
                TapToPayEducationView(userId: userId)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    TapToPaySplashView(userId: "preview-user")
}
