// [APPLE-TTP] TapToPayEducationView.swift
// Req 4.1: Shown immediately after T&C acceptance.
// Req 4.2: Accessible in Settings.
// Req 4.3: Aligned with Apple marketing guidelines for copy and SF Symbols.
// Req 4.4: Demonstrates accepting contactless cards.
// Req 4.5: Demonstrates accepting Apple Pay and digital wallets.

import SwiftUI

/// Merchant education for Tap to Pay on iPhone.
/// Uses Apple-approved copy and SF Symbols per marketing guidelines.
struct TapToPayEducationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var educationManager = TapToPayEducationManager.shared

    let userId: String
    @State private var currentPage = 0

    private let pages: [EducationPage] = [
        EducationPage(
            title: "Welcome to Tap to Pay on iPhone",
            description: "Accept contactless payments right on your iPhone — no extra hardware needed.",
            imageName: "wave.3.right.circle.fill",
            tips: [
                "Accept contactless card payments",
                "Accept Apple Pay and other digital wallets",
                "No card reader or dongle required"
            ]
        ),
        EducationPage(
            // Req 4.4: Must demonstrate contactless card acceptance
            title: "Accepting Contactless Cards",
            description: "When your customer is ready to pay:",
            imageName: "creditcard.fill",
            tips: [
                "1. Enter the amount, then tap the Tap to Pay on iPhone button",
                "2. Ask your customer to hold their card near the top of your iPhone",
                "3. Wait for the confirmation — payment is processed automatically"
            ]
        ),
        EducationPage(
            // Req 4.5: Must demonstrate Apple Pay and other digital wallets
            title: "Accepting Apple Pay & Digital Wallets",
            description: "Customers can also pay with their iPhone, Apple Watch, or other NFC device:",
            imageName: "applelogo",
            tips: [
                "1. Enter the amount, then tap the Tap to Pay on iPhone button",
                "2. Ask your customer to hold their device near the top of your iPhone",
                "3. They authenticate with Face ID, Touch ID, or a passcode",
                "4. Wait for the checkmark — payment is complete"
            ]
        ),
        EducationPage(
            title: "Tips for Success",
            description: "Get the best results every time:",
            imageName: "checkmark.seal.fill",
            tips: [
                "Keep your iPhone charged",
                "Remove thick cases if the NFC read is weak",
                "Hold your iPhone steady during the tap",
                "Ensure you have an active internet connection"
            ]
        ),
        EducationPage(
            title: "How to Enable Tap to Pay",
            description: "Follow these steps to get started:",
            imageName: "list.bullet.clipboard.fill",
            tips: [
                "1. Create or open an event and head to Setup > Payment",
                "2. Configure and enable your payment provider (e.g. Stripe) in the Providers section",
                "3. Enable the Tap to Pay method under Methods and tap the cog to configure it",
                "4. Enable currencies and your payment provider inside the Tap to Pay config",
                "5. Tap to Pay is ready to use!",
                "Tip: to revisit these instructions, go to Setup > Payment > Tap to Pay > Instructions"
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    EducationPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if currentPage == pages.count - 1 {
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
                    Button(action: {
                        withAnimation { currentPage += 1 }
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
                Image(systemName: page.imageName)
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)

                Text(page.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)

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
