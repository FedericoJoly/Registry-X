import SwiftUI

/// Simplified email input sheet for manual payment receipts
struct SimpleEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let onComplete: (String) -> Void
    let onCancel: () -> Void
    
    @State private var email: String = ""
    @FocusState private var isEmailFocused: Bool
    
    private var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)
                    
                    Text("Email Receipt")
                        .font(.title2.bold())
                    
                    Text("Enter customer's email address")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 30)
                
                // Email Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundStyle(.secondary)
                        
                        TextField("customer@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isEmailFocused)
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(12)
                    
                    if !email.isEmpty && !isValidEmail {
                        Label("Please enter a valid email", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onComplete(email)
                        dismiss()
                    }) {
                        Text("Send Receipt")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValidEmail ? Color.blue : Color.gray)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!isValidEmail)
                    
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("Skip")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.systemGray5))
                            .foregroundStyle(.primary)
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            isEmailFocused = true
        }
    }
}
