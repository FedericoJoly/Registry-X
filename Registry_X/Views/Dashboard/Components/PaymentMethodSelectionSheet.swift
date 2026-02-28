import SwiftUI

// MARK: - Payment Method Selection Sheet
struct PaymentMethodSelectionSheet: View {
    let availableMethods: [PaymentMethodOption]
    let currentCurrency: String
    let derivedTotal: Decimal
    let onSelect: (PaymentMethodOption) -> Void
    let onCancel: () -> Void
    var qrAtLimit: Bool = false
    
    private func currencySymbol(for code: String) -> String {
        let locale = Locale.availableIdentifiers
            .map { Locale(identifier: $0) }
            .first { $0.currency?.identifier == code }
        return locale?.currencySymbol ?? code
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select Payment Method")
                    .font(.title2)
                    .bold()
                    .padding(.top)
                
                Text(currencySymbol(for: currentCurrency) + derivedTotal.formatted(.number.precision(.fractionLength(2))))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                if availableMethods.isEmpty {
                    ContentUnavailableView(
                        "No Payment Methods",
                        systemImage: "creditcard.trianglebadge.exclamationmark",
                        description: Text("No payment methods are configured for this currency. Please add payment methods in Setup.")
                    )
                    .padding(.top, 40)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(availableMethods) { method in
                                let isQRMethod = method.icon.contains("qrcode") && method.enabledProviders.contains("stripe")
                                let isDisabled = isQRMethod && qrAtLimit
                                PaymentMethodButton(
                                    method: method,
                                    isDisabled: isDisabled,
                                    disabledCaption: isDisabled ? "Complete the current pending QR transactions first" : nil
                                ) {
                                    if !isDisabled {
                                        onSelect(method)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

struct PaymentMethodButton: View {
    let method: PaymentMethodOption
    var isDisabled: Bool = false
    var disabledCaption: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: method.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(isDisabled ? Color(UIColor.systemGray3) : method.color)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(method.name)
                        .font(.headline)
                        .foregroundStyle(isDisabled ? .secondary : .primary)

                    if let caption = disabledCaption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(isDisabled ? Color(UIColor.systemGray3) : .secondary)
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
            .opacity(isDisabled ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - PaymentMethodOption Extension
extension PaymentMethodOption {
    func toPaymentMethod() -> PaymentMethod {
        // Map icon to PaymentMethod enum
        switch icon {
        case "banknote":
            return .cash
        case "creditcard", "creditcard.fill":
            return .card
        case "building.columns", "banknote.fill":
            return .transfer
        default:
            return .other
        }
    }
}
