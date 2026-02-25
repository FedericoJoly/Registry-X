import SwiftUI

struct CustomDiscountSheet: View {
    // Callbacks
    let onApply: (Decimal, Bool) -> Void   // (value, isPercentage)
    let onClear:  () -> Void
    let onCancel: () -> Void

    // Current value for pre-filling when re-opening
    let currentValue: Decimal?
    let currentIsPercentage: Bool

    @FocusState private var fieldFocused: Bool

    // Local state
    @State private var amountText: String = ""
    @State private var isPercentage: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("Custom Discount")
                .font(.headline)
                .padding(.top, 20)

            // Amount field
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    .focused($fieldFocused)
                    .font(.system(size: 22, weight: .semibold))
                if !amountText.isEmpty {
                    Button { amountText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            // Value / Percentage picker
            Picker("Type", selection: $isPercentage) {
                Text("Value").tag(false)
                Text("Percentage").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            // Buttons
            HStack(spacing: 12) {
                // Cancel
                Button { onCancel() } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(UIColor.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }

                // Clear (only when there's an active discount)
                if currentValue != nil {
                    Button {
                        onClear()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .cornerRadius(12)
                    }
                }

                // OK
                Button {
                    let normalised = amountText.replacingOccurrences(of: ",", with: ".")
                    if let value = Decimal(string: normalised), value > 0 {
                        onApply(value, isPercentage)
                    }
                } label: {
                    Text("OK")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(okEnabled ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(!okEnabled)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .onAppear {
            // Pre-fill with existing discount if any
            if let v = currentValue {
                amountText = v.formatted(.number.precision(.fractionLength(2)))
                isPercentage = currentIsPercentage
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                fieldFocused = true
            }
        }
    }

    private var okEnabled: Bool {
        let normalised = amountText.replacingOccurrences(of: ",", with: ".")
        if let value = Decimal(string: normalised), value > 0 { return true }
        return false
    }
}
