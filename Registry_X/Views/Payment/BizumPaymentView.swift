import SwiftUI

struct BizumPaymentView: View {
    let amount: Decimal
    let currency: String
    let phoneNumber: String
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var formattedPhoneNumber: String {
        // Format: +34 XXX XXX XXX
        let cleaned = phoneNumber.replacingOccurrences(of: "+34", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 9 else { return phoneNumber }
        
        let part1 = String(cleaned.prefix(3))
        let part2 = String(cleaned.dropFirst(3).prefix(3))
        let part3 = String(cleaned.suffix(3))
        return "+34 \(part1) \(part2) \(part3)"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    VStack(spacing: 32) {
                        // Bizum Logo
                        Image("bizum_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 100)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        
                        // Amount
                        Text(currency + amount.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Divider()
                            .padding(.horizontal, 40)
                        
                        // Phone Number
                        VStack(spacing: 8) {
                            Text("Send payment to:")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Text(formattedPhoneNumber)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .foregroundStyle(.green)
                                .tracking(1)
                        }
                        
                        // Instructions
                        Text("Customer should open their Bizum app and send the payment to the number above")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Spacer()
                    
                    // Done Button
                    Button(action: {
                        onComplete()
                        dismiss()
                    }) {
                        Text("Payment Received")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Bizum Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    BizumPaymentView(
        amount: 42.50,
        currency: "€",
        phoneNumber: "+34612345678",
        onComplete: {},
        onCancel: {}
    )
}
