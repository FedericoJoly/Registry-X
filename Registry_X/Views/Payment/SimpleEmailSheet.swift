import SwiftUI

/// Simplified email input sheet for manual payment receipts
struct SimpleEmailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onComplete: (String) -> Void
    let onCancel: () -> Void
    var initialEmail: String = ""

    @State private var email: String = ""
    @FocusState private var isEmailFocused: Bool

    private var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Drag indicator ─────────────────────────────────────────────
            Capsule()
                .fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // ── Header row ─────────────────────────────────────────────────
            HStack {
                Image(systemName: "envelope.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Email Receipt")
                    .font(.headline)
                Spacer()
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(UIColor.systemGray3))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)

            Text("Enter customer's email address")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // ── Email field ────────────────────────────────────────────────
            HStack {
                Image(systemName: "envelope")
                    .foregroundStyle(.secondary)
                TextField("customer@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isEmailFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 20)

            if !email.isEmpty && !isValidEmail {
                Label("Please enter a valid email", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }

            // ── Send button ────────────────────────────────────────────────
            Button(action: {
                onComplete(email)
                dismiss()
            }) {
                Text("Send Receipt")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isValidEmail ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(!isValidEmail)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .onAppear {
            if !initialEmail.isEmpty { email = initialEmail }
            isEmailFocused = true
        }
    }
}
