import SwiftUI
import CoreImage.CIFilterBuiltins

struct StripeQRPaymentView: View {
    let amount: Decimal
    let currency: String
    let description: String
    let companyName: String?
    let lineItems: [[String: Any]]?
    let backendURL: String
    let onSuccess: (String) -> Void // Session ID
    let onCancel: () -> Void
    
    @State private var qrCodeImage: UIImage?
    @State private var checkoutURL: String?
    @State private var sessionId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCompleteButton = false
    @State private var isPolling = false
    @State private var pollingTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Generating QR code...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange)
                        
                        Text("QR Code Failed")
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
                } else if let qrImage = qrCodeImage {
                    ScrollView {
                        VStack(spacing: 24) {
                            Text("Scan to Pay")
                                .font(.title2.bold())
                            
                            Text("\(formattedAmount) \(currency.uppercased())")
                                .font(.title.bold())
                            
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            
                            // QR Code
                            VStack(spacing: 12) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 250, height: 250)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(16)
                                    .shadow(radius: 10)
                                
                                if showCompleteButton {
                                    Button(action: {
                                        if let sessionId = sessionId {
                                            onSuccess(sessionId)
                                            dismiss()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("Payment Complete")
                                        }
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.green)
                                        .cornerRadius(12)
                                    }
                                    .padding(.top, 8)
                                } else {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Checking payment status...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            
                            Divider()
                                .padding(.vertical)
                            
                            // Instructions
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Instructions")
                                    .font(.headline)
                                
                                instructionRow(number: "1", text: "Scan the QR code above")
                                instructionRow(number: "2", text: "Complete payment on your device")
                                instructionRow(number: "3", text: "App will detect completion automatically")
                                
                                if showCompleteButton {
                                    Text("Or tap 'Payment Complete' if needed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            
                            Button("Cancel Payment") {
                                pollingTask?.cancel()
                                onCancel()
                                dismiss()
                            }
                            .foregroundStyle(.red)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("QR Code Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pollingTask?.cancel()
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            await setupQRCode()
            // Show manual complete button after 15 seconds as fallback
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            showCompleteButton = true
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }
    
    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSNumber) ?? "\(amount)"
    }
    
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.body.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.body)
        }
    }
    
    private func setupQRCode() async {
        do {
            // Create checkout session
            let service = StripeNetworkService(backendURL: backendURL)
            let response = try await service.createCheckoutSession(
                amount: amount,
                currency: currency,
                description: description,
                companyName: companyName,
                lineItems: lineItems,
                metadata: ["source": "Registry_X"]
            )
            
            // Generate QR code
            let qrImage = generateQRCode(from: response.url)
            
            await MainActor.run {
                self.qrCodeImage = qrImage
                self.checkoutURL = response.url
                self.sessionId = response.sessionId
                self.isLoading = false
                
                // Start polling for payment completion
                self.isPolling = true
                self.pollingTask = Task {
                    await pollForCompletion(sessionId: response.sessionId)
                }
            }
            
        } catch let error as StripeNetworkError {
            await MainActor.run {
                self.errorMessage = error.userMessage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to create QR code: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func pollForCompletion(sessionId: String) async {
        // Poll for up to 5 minutes (20 attempts x 15 seconds)
        for attempt in 0..<20 {
            if Task.isCancelled { return }
            
            // Wait before checking (except first attempt)
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            } else {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds for first check
            }
            
            // Check session status via backend
            do {
                let service = StripeNetworkService(backendURL: backendURL)
                let statusDict = try await service.checkSessionStatus(sessionId: sessionId)
                
                if Task.isCancelled { return }
                
                // Check if payment succeeded - Stripe's field is "payment_status"
                if let paymentStatus = statusDict["status"] as? String,
                   paymentStatus == "paid" || paymentStatus == "complete" {
                    await MainActor.run {
                        onSuccess(sessionId)
                        dismiss()
                    }
                    return
                }
            } catch {
                // Continue polling on error (session might not exist yet or network issues)
            }
        }
        
        // Polling timed out - manual button already showing
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = string.data(using: .utf8) else { return nil }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage else { return nil }
        
        // Scale up the QR code
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}
