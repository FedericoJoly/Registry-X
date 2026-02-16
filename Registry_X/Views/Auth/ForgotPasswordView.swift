import SwiftUI
import SwiftData

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService
    @Environment(\.modelContext) private var modelContext
    
    @State private var email: String = ""
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        VStack(spacing: 25) {
            
            // Back Button handled by NavigationStack automatically if pushed.
            // But if we want custom back button style as per design, we might need to hide default.
            // For now, standard back button is fine.
            
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "key.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(-45))
            }
            .padding(.bottom, 10)
            
            // Title & Subtitle
            VStack(spacing: 12) {
                Text("Forgot Password")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter your email address and we will send\nyou a temporary password")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Email Input
            VStack(alignment: .leading, spacing: 5) {
                Text("Email Address")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                TextField("Enter your email", text: $email)
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }
            .padding(.top, 20)
            
            // Send Button
            Button(action: sendRecoveryEmail) {
                Text("Send Recovery Email")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.top, 10)
            
            Spacer()
            Spacer()
        }
        .padding(30)
        .background(Color(UIColor.systemGray6))
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {
                if isSuccess {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func sendRecoveryEmail() {
        if email.isEmpty {
            alertTitle = "Invalid Email"
            alertMessage = "Please enter your email address."
            isSuccess = false
            showingAlert = true
            return
        }
        
        do {
            try authService.resetPassword(email: email, context: modelContext)
            alertTitle = "Email Sent"
            alertMessage = "A temporary password has been sent to \(email)."
            isSuccess = true
            showingAlert = true
        } catch {
            alertTitle = "Error"
            alertMessage = error.localizedDescription
            isSuccess = false
            showingAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
            .environment(AuthService())
    }
}
