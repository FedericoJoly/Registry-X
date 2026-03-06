// [APPLE-TTP] TapToPaySplashView.swift
// Req 3.1: Highly-visible, easily discoverable TTP communication.
// Req 3.3: All eligible users must see this at least once.
//          When AppConfig.isAppleApprovalMode is true, "Maybe Later" is hidden — user must proceed.

import SwiftUI

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
                colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Icon — Apple-required SF Symbol
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 150, height: 150)

                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 88))
                        .foregroundStyle(.blue)
                }

                // Title
                Text("Tap to Pay on iPhone")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)

                // Description — must be "highly visible" (req 3.1)
                VStack(spacing: 14) {
                    Text("Accept contactless payments directly on your iPhone")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text("No additional hardware required — powered by Apple and Stripe")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 36)

                // Feature rows
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "creditcard.fill",
                        title: "Contactless Cards",
                        description: "Visa, Mastercard, Amex and more"
                    )
                    FeatureRow(
                        icon: "applelogo",
                        title: "Apple Pay & Digital Wallets",
                        description: "iPhone, Apple Watch, and other devices"
                    )
                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "Secure & Private",
                        description: "End-to-end encrypted — no card data stored"
                    )
                }
                .padding(.horizontal, 36)
                .padding(.top, 16)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Primary CTA — always visible
                    Button(action: {
                        educationManager.markSplashShown(for: userId)
                        showTerms = true
                    }) {
                        Text("Set Up Tap to Pay on iPhone")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(14)
                    }

                    // [APPLE-TTP] "Maybe Later" hidden in approval mode (req 3.3)
                    // Shown post-approval to give operators more flexibility.
                    if !AppConfig.isAppleApprovalMode {
                        Button(action: {
                            educationManager.markSplashShown(for: userId)
                            dismiss()
                        }) {
                            Text("Maybe Later")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 32)
            }
        }
        // T&C Modal first
        .sheet(isPresented: $showTerms) {
            TapToPayTermsView(userId: userId) {
                // After T&C accepted → dismiss T&C, then show education
                showTerms = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showEducation = true
                }
            }
        }
        // Education modal after T&C
        .sheet(isPresented: $showEducation) {
            // Once education is dismissed, also dismiss the splash
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
