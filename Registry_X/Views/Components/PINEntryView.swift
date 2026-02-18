import SwiftUI

/// Reusable PIN entry sheet with visual error feedback (red label for 2s on wrong PIN)
struct PINEntryView: View {
    let title: String
    let message: String
    /// Return nil on success, or an error string to show and stay open
    let onSubmit: (String) -> String?
    let onCancel: () -> Void
    
    @State private var pin: String = ""
    @State private var errorMessage: String? = nil
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 8)
            
            // Message
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // PIN field
            VStack(alignment: .leading, spacing: 6) {
                Text("PIN")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(errorMessage != nil ? .red : .secondary)
                    .animation(.easeInOut(duration: 0.2), value: errorMessage != nil)
                
                SecureField("Enter PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .focused($isFocused)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor.systemGray6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(errorMessage != nil ? Color.red : Color(UIColor.systemGray4),
                                    lineWidth: errorMessage != nil ? 1.5 : 1)
                            .animation(.easeInOut(duration: 0.2), value: errorMessage != nil)
                    )
                
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 4)
            .animation(.easeInOut(duration: 0.2), value: errorMessage)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(UIColor.systemGray5))
                .foregroundStyle(.primary)
                .cornerRadius(10)
                
                Button("Confirm") {
                    if let error = onSubmit(pin) {
                        // Stay open — show error for 2 seconds
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        withAnimation { errorMessage = error }
                        pin = ""
                        isFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { errorMessage = nil }
                        }
                    } else {
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(10)
            }
        }
        .padding(24)
        .interactiveDismissDisabled()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
}
