import SwiftUI

/// Dedicated Terms & Conditions acceptance screen for Tap to Pay on iPhone
/// Shown BEFORE education screens as per Apple requirements
struct TapToPayTermsView: View {
    @Environment(\.dismiss) private var dismiss
    let userId: String
    let onAccept: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                        
                        Text("Terms & Conditions")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        
                        Text("Review and accept to use Tap to Pay on iPhone")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    Divider()
                    
                    // Terms Content
                    VStack(alignment: .leading, spacing: 20) {
                        TermSection(
                            icon: "checkmark.seal.fill",
                            title: "Service Provider",
                            description: "Tap to Pay on iPhone is provided by Apple Inc. Payment processing is handled securely through Stripe."
                        )
                        
                        TermSection(
                            icon: "lock.shield.fill",
                            title: "Payment Card Industry Standards",
                            description: "All transactions comply with PCI-DSS requirements for secure payment processing."
                        )
                        
                        TermSection(
                            icon: "building.2.fill",
                            title: "Business Authorization",
                            description: "By accepting, you confirm that you are authorized to accept payments on behalf of your business."
                        )
                        
                        TermSection(
                            icon: "doc.plaintext.fill",
                            title: "Data Processing",
                            description: "Transaction data is processed according to Apple's privacy policy and Stripe's Terms of Service."
                        )
                        
                        TermSection(
                            icon:" info.circle.fill",
                            title: "Device Requirements",
                            description: "Tap to Pay on iPhone requires an iPhone XS or later running iOS 15.4 or later."
                        )
                        
                        TermSection(
                            icon: "exclamationmark.triangle.fill",
                            title: "Merchant Responsibility",
                            description: "You are responsible for ensuring accurate transaction amounts and proper customer authorization."
                        )
                    }
                    .padding(.horizontal, 8)
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
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
            .safeAreaInset(edge: .bottom) {
                // Accept Button (Fixed at bottom)
                VStack(spacing: 12) {
                    Button(action: {
                        TapToPayEducationManager.shared.markTermsAccepted(for: userId)
                        onAccept()
                    }) {
                        Text("Accept Terms & Conditions")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(14)
                    }
                    
                    Text("By accepting, you agree to Apple's Tap to Pay on iPhone Terms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(UIColor.systemBackground).opacity(0.95))
            }
        }
    }
}

struct TermSection: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    TapToPayTermsView(userId: "preview") {
    }
}
