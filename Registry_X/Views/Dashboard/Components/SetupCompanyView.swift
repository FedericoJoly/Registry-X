import SwiftUI

struct SetupCompanyView: View {
    @Binding var draft: DraftEventSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 5) {
                Text("Company")
                    .font(.headline)
                Text("Configure your company information for emails and receipts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Company Name
            VStack(alignment: .leading, spacing: 8) {
                Label("Company Name", systemImage: "building.2")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Enter company name", text: $draft.companyName)
                    .textFieldStyle(.roundedBorder)
                Text("Used in Stripe payments and receipts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // From Display Name
            VStack(alignment: .leading, spacing: 8) {
                Label("Email FROM Name", systemImage: "person.text.rectangle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("e.g., Sales Team", text: $draft.fromName)
                    .textFieldStyle(.roundedBorder)
                Text("Display name for outgoing emails")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // From Email Address
            VStack(alignment: .leading, spacing: 8) {
                Label("Email FROM Address", systemImage: "envelope")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("e.g., sales@yourcompany.com", text: $draft.fromEmail)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                if !draft.fromEmail.isEmpty && !isValidEmail(draft.fromEmail) {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Please enter a valid email address")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else if !draft.fromEmail.isEmpty {
                    Text("Email address for outgoing receipts and notifications")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}
