// [APPLE-TTP] PaymentMethodSelectionSheet.swift
// Req 5.1: Obvious, prominent TTP button.
// Req 5.2: TTP at the top, visible without scrolling.
// Req 5.3: TTP button never grayed out regardless of setup state.

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

    /// [APPLE-TTP] Req 5.2: TTP (creditcard+stripe) must be first in the list.
    private var orderedMethods: [PaymentMethodOption] {
        let ttpMethods = availableMethods.filter { isTTPMethod($0) }
        let others = availableMethods.filter { !isTTPMethod($0) }
        return ttpMethods + others
    }

    private func isTTPMethod(_ method: PaymentMethodOption) -> Bool {
        method.icon.contains("creditcard") && method.enabledProviders.contains("stripe")
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
                            ForEach(orderedMethods) { method in
                                let isTTP = isTTPMethod(method)
                                let isQRMethod = method.icon.contains("qrcode") && method.enabledProviders.contains("stripe")
                                let isDisabled = isQRMethod && qrAtLimit

                                if isTTP {
                                    // [APPLE-TTP] Req 5.1/5.3: Special TTP button — never disabled,
                                    // uses Apple's required SF Symbol and official copy.
                                    TapToPayButton(method: method) {
                                        onSelect(method)
                                    }
                                } else {
                                    PaymentMethodButton(
                                        method: method,
                                        isDisabled: isDisabled,
                                        disabledCaption: isDisabled ? "Complete current pending QR transactions first" : nil
                                    ) {
                                        if !isDisabled {
                                            onSelect(method)
                                        }
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

// MARK: - [APPLE-TTP] Dedicated Tap to Pay button (Reqs 5.1, 5.2, 5.3)

/// Apple HIG-compliant: uses wave.3.right.circle.fill + "Tap to Pay on iPhone" copy.
/// NEVER disabled or grayed out — if user hasn't accepted T&C, the action
/// intercepts and shows onboarding (handled in PanelView's onSelect callback).
struct TapToPayButton: View {
    let method: PaymentMethodOption
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // [APPLE-TTP] Required SF Symbol per Apple HIG
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.blue)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    // [APPLE-TTP] Required copy per Apple HIG
                    Text("Tap to Pay on iPhone")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Contactless cards, Apple Pay & digital wallets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        // [APPLE-TTP] Req 5.3: Never disabled
    }
}

// MARK: - Standard payment method button

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
