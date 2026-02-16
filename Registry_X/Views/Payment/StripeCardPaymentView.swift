import SwiftUI
import StripePaymentSheet

struct StripeCardPaymentView: View {
    let amount: Decimal
    let currency: String
    let description: String
    let lineItems: [[String: Any]]?
    let backendURL: String
    let publishableKey: String
    let onSuccess: (String) -> Void // Payment Intent ID
    let onCancel: () -> Void
    
    @State private var paymentSheet: PaymentSheet?
    @State private var clientSecret: String?
    @State private var paymentIntentId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Preparing payment...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange)
                        
                        Text("Payment Setup Failed")
                            .font(.title2.bold())
                        
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Close") {
                            onCancel()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        
                        Text("Ready to Pay")
                            .font(.title2.bold())
                        
                        Text("\(formattedAmount) \(currency.uppercased())")
                            .font(.title.bold())
                        
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Spacer()
                        
                        Button(action: presentPaymentSheet) {
                            HStack {
                                Image(systemName: "creditcard")
                                Text("Pay Now")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Card Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            await setupPaymentSheet()
        }
    }
    
    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSNumber) ?? "\(amount)"
    }
    
    private func setupPaymentSheet() async {
        do {
            // Configure Stripe
            STPAPIClient.shared.publishableKey = publishableKey
            
            // Create payment intent
            let service = StripeNetworkService(backendURL: backendURL)
            let response = try await service.createPaymentIntent(
                amount: amount,
                currency: currency,
                description: description,
                lineItems: lineItems,
                metadata: ["source": "Registry_X"]
            )
            
            // Configure payment sheet
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "Registry_X"
            configuration.allowsDelayedPaymentMethods = false
            
            await MainActor.run {
                self.clientSecret = response.clientSecret
                self.paymentIntentId = response.intentId
                self.paymentSheet = PaymentSheet(
                    paymentIntentClientSecret: response.clientSecret,
                    configuration: configuration
                )
                self.isLoading = false
            }
            
        } catch let error as StripeNetworkError {
            await MainActor.run {
                self.errorMessage = error.userMessage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to setup payment: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func presentPaymentSheet() {
        guard let paymentSheet = paymentSheet else { return }
        
        // Present the payment sheet
        paymentSheet.present(from: getRootViewController()) { paymentResult in
            switch paymentResult {
            case .completed:
                // Payment succeeded
                onSuccess(self.paymentIntentId ?? "")
                dismiss()
                
            case .canceled:
                // User canceled
                onCancel()
                
            case .failed(let error):
                // Payment failed
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func getRootViewController() -> UIViewController {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = scene.windows.first?.rootViewController else {
            return UIViewController()
        }
        
        // Find the topmost presented view controller
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }
        
        return topController
    }
}
