import SwiftUI

struct StripeBackendTestView: View {
    let backendURL: String
    
    @State private var testResult: String = "Ready to test"
    @State private var isTesting = false
    @State private var testSuccess = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Stripe Backend Test")
                    .font(.title2.bold())
                
                Text("Backend URL:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(backendURL)
                    .font(.caption.monospaced())
                    .padding(8)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                
                Divider()
                
                // Test Result
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: testSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(testSuccess ? .green : .blue)
                        Text("Test Result")
                            .font(.headline)
                    }
                    
                    ScrollView {
                        Text(testResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(8)
                    }
                    .frame(height: 200)
                }
                
                Spacer()
                
                // Test Buttons
                VStack(spacing: 12) {
                    Button(action: testHealthCheck) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "heart.fill")
                                Text("Test Health Check")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isTesting)
                    
                    Button(action: testPaymentIntent) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "creditcard.fill")
                                Text("Test Payment Intent")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isTesting)
                    
                    Button(action: testCheckoutSession) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "qrcode")
                                Text("Test Checkout Session")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isTesting)
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Test Functions
    
    func testHealthCheck() {
        isTesting = true
        testResult = "Testing health endpoint...\n"
        
        Task {
            do {
                guard let url = URL(string: "\(backendURL)/health") else {
                    updateResult("❌ Invalid URL")
                    return
                }
                
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    updateResult("❌ Invalid response")
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let prettyJSON = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
                        let jsonString = String(data: prettyJSON, encoding: .utf8) ?? ""
                        updateResult("✅ Health check passed!\n\n\(jsonString)", success: true)
                    } else {
                        updateResult("✅ Health check passed!\n\nStatus: \(httpResponse.statusCode)", success: true)
                    }
                } else {
                    updateResult("❌ Health check failed\nStatus: \(httpResponse.statusCode)")
                }
            } catch {
                updateResult("❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    func testPaymentIntent() {
        isTesting = true
        testResult = "Creating payment intent...\n"
        
        Task {
            do {
                let service = StripeNetworkService(backendURL: backendURL)
                let response = try await service.createPaymentIntent(
                    amount: 10.00,
                    currency: "USD",
                    description: "Test Payment",
                    metadata: ["test": "true"]
                )
                
                let resultText = """
                ✅ Payment Intent Created!
                
                Intent ID: \(response.intentId)
                Amount: $\(Double(response.amount) / 100)
                Currency: \(response.currency.uppercased())
                Client Secret: \(response.clientSecret.prefix(20))...
                """
                
                updateResult(resultText, success: true)
            } catch let error as StripeNetworkError {
                updateResult("❌ \(error.userMessage)")
            } catch {
                updateResult("❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    func testCheckoutSession() {
        isTesting = true
        testResult = "Creating checkout session...\n"
        
        Task {
            do {
                let service = StripeNetworkService(backendURL: backendURL)
                let response = try await service.createCheckoutSession(
                    amount: 15.50,
                    currency: "EUR",
                    description: "Test QR Payment",
                    metadata: ["test": "qr"]
                )
                
                let resultText = """
                ✅ Checkout Session Created!
                
                Session ID: \(response.sessionId)
                URL: \(response.url)
                
                (This URL would be encoded in a QR code)
                """
                
                updateResult(resultText, success: true)
            } catch let error as StripeNetworkError {
                updateResult("❌ \(error.userMessage)")
            } catch {
                updateResult("❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    func updateResult(_ text: String, success: Bool = false) {
        testResult = text
        testSuccess = success
        isTesting = false
    }
}
