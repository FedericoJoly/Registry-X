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
                // Header — compact to maximise web view height
                HStack(spacing: 10) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tap to Pay on iPhone")
                            .font(.subheadline.bold())
                        Text("Review and accept Apple's Terms & Conditions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))

                Divider()

                // Apple's official Terms embedded in a web view
                SafariWebView(url: termsURL)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Decline") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        TapToPayEducationManager.shared.markTermsAccepted(for: userId)
                        onAccept()
                    }) {
                        Label("Accept & Continue", systemImage: "checkmark")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
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
