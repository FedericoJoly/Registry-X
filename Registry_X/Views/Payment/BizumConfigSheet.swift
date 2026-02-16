import SwiftUI

struct BizumConfigView: View {
    @Binding var phoneNumber: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var localPhoneNumber: String = ""
    @State private var showingValidationError = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Text("+34")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                        
                        TextField("Phone Number", text: $localPhoneNumber)
                            .keyboardType(.numberPad)
                            .textContentType(.telephoneNumber)
                    }
                } header: {
                    Text("Bizum Phone Number")
                } footer: {
                    Text("Enter the 9-digit Spanish mobile number where customers will send Bizum payments.")
                }
                
                if showingValidationError {
                    Section {
                        Label("Please enter a valid 9-digit phone number", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Bizum Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConfiguration()
                    }
                }
            }
            .onAppear {
                // Load existing phone number if available
                if !phoneNumber.isEmpty {
                    // Remove +34 prefix if present
                    localPhoneNumber = phoneNumber.replacingOccurrences(of: "+34", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        }
    }
    
    private func saveConfiguration() {
        // Validate phone number (must be 9 digits)
        let cleanedNumber = localPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If phone number is being cleared/deleted, save empty string
        if cleanedNumber.isEmpty {
            phoneNumber = ""
            dismiss()
            return
        }
        
        guard cleanedNumber.count == 9, cleanedNumber.allSatisfy({ $0.isNumber }) else {
            showingValidationError = true
            return
        }
        
        // Save with +34 prefix
        phoneNumber = "+34" + cleanedNumber
        dismiss()
    }
}

#Preview {
    BizumConfigView(phoneNumber: .constant(""))
}
