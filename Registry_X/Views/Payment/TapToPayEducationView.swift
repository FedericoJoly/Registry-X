import SwiftUI

/// Fallback merchant education view for iOS versions prior to 18
/// Uses Apple-approved content from Tap to Pay Marketing Toolkit
struct TapToPayEducationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var educationManager = TapToPayEducationManager.shared
    
    let userId: String
    
    @State private var currentPage = 0
    
    private let pages: [EducationPage] = [
        EducationPage(
            title: "Welcome to Tap to Pay on iPhone",
            description: "Accept contactless payments right on your iPhone—no extra hardware needed.",
            imageName: "wave.3.right.circle.fill",
            tips: [
                "Accept card payments",
                "Accept Apple Pay",
                "Accept other digital wallets"
            ]
        ),
        EducationPage(
            title: "Accepting Contactless Cards",
            description: "When your customer is ready to pay:",
            imageName: "creditcard.fill",
            tips: [
                "1. Enter the amount and tap 'Tap to Pay'",
                "2. Ask your customer to hold their card near the top of your iPhone",
                "3. Wait for the checkmark and confirmation"
            ]
        ),
        EducationPage(
            title: "Accepting Apple Pay & Digital Wallets",
            description: "Customers can also pay with their iPhone or Apple Watch:",
            imageName: "applelogo",
            tips: [
                "1. Enter the amount and tap 'Tap to Pay'",
                "2. Ask your customer to hold their device near the top of your iPhone",
                "3. They'll authenticate with Face ID or Touch ID",
                "4. Wait for the checkmark and confirmation"
            ]
        ),
        EducationPage(
            title: "Tips for Success",
            description: "Get the best results:",
            imageName: "checkmark.circle.fill",
            tips: [
                "Keep your iPhone charged",
                "Remove thick cases if needed",
                "Hold steady during the tap",
                "Ensure good internet connection"
            ]
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Page Content
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    EducationPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            
            // Bottom buttons
            VStack(spacing: 12) {
                if currentPage == pages.count - 1 {
                    // Last page - Get Started button
                    Button(action: {
                        educationManager.markEducationComplete(for: userId)
                        dismiss()
                    }) {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                } else {
                    // Other pages - Next button
                    Button(action: {
                        withAnimation {
                            currentPage += 1
                        }
                    }) {
                        Text("Next")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                
                // Skip button
                if currentPage < pages.count - 1 {
                    Button(action: {
                        educationManager.markEducationComplete(for: userId)
                        dismiss()
                    }) {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    educationManager.markEducationComplete(for: userId)
                    dismiss()
                }
            }
        }
    }
}

struct EducationPage {
    let title: String
    let description: String
    let imageName: String
    let tips: [String]
}

struct EducationPageView: View {
    let page: EducationPage
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Icon
                Image(systemName: page.imageName)
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                
                // Title
                Text(page.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                // Description
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                
                // Tips
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(page.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text(tip)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                
                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }
}

#Preview {
    NavigationView {
        TapToPayEducationView(userId: "preview-user")
    }
}
