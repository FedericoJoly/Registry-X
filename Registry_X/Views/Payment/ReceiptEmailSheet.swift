import SwiftUI

struct ReceiptEmailSheet: View {
    let paymentIntentId: String
    let backendURL: String
    let onComplete: (String) -> Void // Now passes the email back
    let onCancel: () -> Void
    
    @State private var email = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    @FocusState private var isEmailFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon and title
                VStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Email Receipt")
                        .font(.title2.bold())
                    
                    Text("Enter customer's email to send receipt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                // Email input
                VStack(alignment: .leading, spacing: 8) {
                    TextField("customer@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($isEmailFocused)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    
                    if !email.isEmpty && !isValidEmail {
                        Label("Please enter a valid email address", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: submitEmail) {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text("Send Receipt")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canSubmit ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!canSubmit || isSubmitting)
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .alert("Receipt Sent!", isPresented: $showSuccess) {
            Button("Done") {
                onComplete(email) // Pass the email back
            }
        } message: {
            Text("The receipt has been sent to \(email)")
        }
        .onAppear {
            // Auto-focus email field when sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isEmailFocused = true
            }
        }
    }
    
    private var isValidEmail: Bool {
        let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
    
    private var canSubmit: Bool {
        !email.isEmpty && isValidEmail && !isSubmitting
    }
    
    private func submitEmail() {
        guard canSubmit else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                let service = StripeNetworkService(backendURL: backendURL)
                _ = try await service.sendReceiptEmail(
                    paymentIntentId: paymentIntentId,
                    email: email
                )
                
                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                }
            } catch let error as StripeNetworkError {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.userMessage
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to send receipt: \(error.localizedDescription)"
                }
            }
        }
    }
}
