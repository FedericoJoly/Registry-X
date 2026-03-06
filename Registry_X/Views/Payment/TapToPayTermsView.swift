// [APPLE-TTP] TapToPayTermsView.swift
// Shows Apple's official Tap to Pay on iPhone Terms & Conditions.
// Req 3.5: Must have a clear action to trigger acceptance of TTP T&C.

import SwiftUI
import SafariServices

/// Shows Apple's official Tap to Pay on iPhone Terms & Conditions in a web view.
/// The user must scroll and explicitly accept before proceeding to education.
struct TapToPayTermsView: View {
    @Environment(\.dismiss) private var dismiss
    let userId: String
    let onAccept: () -> Void

    // Apple's official TTP Platform Terms & Conditions URL
    // [APPLE-TTP] Official URL provided by Apple in their TTP entitlement email
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/business-services/tap-to-pay-on-iphone/terms-en.html")!

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.blue)
                        .padding(.top, 20)

                    Text("Tap to Pay on iPhone")
                        .font(.title2.bold())

                    Text("Review and accept Apple's Terms & Conditions to use Tap to Pay on iPhone")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.secondarySystemBackground))

                Divider()

                // Apple's official Terms embedded in a web view
                SafariWebView(url: termsURL)

                Divider()

                // Accept + Decline bottom bar
                VStack(spacing: 10) {
                    Button(action: {
                        TapToPayEducationManager.shared.markTermsAccepted(for: userId)
                        onAccept()
                    }) {
                        Label("Accept & Continue", systemImage: "checkmark")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(14)
                    }

                    Text("By accepting, you agree to Apple's Tap to Pay on iPhone Platform Terms & Conditions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(UIColor.systemBackground).opacity(0.97))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Decline") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - Thin SafariView wrapper

struct SafariWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview {
    TapToPayTermsView(userId: "preview") {}
}
