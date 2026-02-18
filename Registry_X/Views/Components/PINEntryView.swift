import SwiftUI

/// Reusable PIN entry sheet with visual error feedback (red label for 2s on wrong PIN)
struct PINEntryView: View {
    let title: String
    let message: String
    let onSubmit: (String) -> Bool // returns true if PIN correct
    let onCancel: () -> Void
    
    @State private var pin: String = ""
    @State private var isError: Bool = false
    @FocusState private var isFocused: Bool
    
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
                    .foregroundStyle(isError ? .red : .secondary)
                    .animation(.easeInOut(duration: 0.2), value: isError)
                
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
                            .stroke(isError ? Color.red : Color(UIColor.systemGray4), lineWidth: isError ? 1.5 : 1)
                            .animation(.easeInOut(duration: 0.2), value: isError)
                    )
                
                if isError {
                    Text("Incorrect PIN. Try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 4)
            .animation(.easeInOut(duration: 0.2), value: isError)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(UIColor.systemGray5))
                .foregroundStyle(.primary)
                .cornerRadius(10)
                
                Button("Confirm") {
                    let correct = onSubmit(pin)
                    if !correct {
                        // Show red error state for 2 seconds
                        withAnimation {
                            isError = true
                        }
                        pin = ""
                        isFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                isError = false
                            }
                        }
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
}
