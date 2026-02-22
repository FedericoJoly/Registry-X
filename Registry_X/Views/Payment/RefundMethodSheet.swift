import SwiftUI

/// Sheet for choosing the refund method for Card or QR transactions.
/// Always offers the original payment method + Cash as options.
struct RefundMethodSheet: View {
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction
    let onSelect: (RefundService.RefundMethod) -> Void

    private var paymentLabel: String {
        if transaction.isNWaySplit {
            return "Original Split (proportional)"
        }
        let icon = transaction.paymentMethodIcon ?? ""
        if icon.contains("qrcode") { return "QR Code (Stripe)" }
        return "Card (Stripe)"
    }

    private var paymentIcon: String {
        if transaction.isNWaySplit { return "arrow.triangle.branch" }
        let icon = transaction.paymentMethodIcon ?? ""
        if icon.contains("qrcode") { return "qrcode" }
        return "creditcard"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Header
            HStack {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Refund Method")
                        .font(.headline)
                    if let ref = transaction.transactionRef {
                        Text("Ref: \(ref)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(UIColor.systemGray3))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)

            Divider()

            // Amount
            HStack {
                Text("Amount to refund")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(amountText)
                    .font(.title3.bold())
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Options
            VStack(spacing: 12) {
                // Original method (Stripe)
                RefundOptionRow(
                    icon: paymentIcon,
                    iconColor: .blue,
                    title: paymentLabel,
                    subtitle: "Stripe processes the refund automatically",
                    action: {
                        onSelect(.stripe)
                        dismiss()
                    }
                )

                // Cash
                RefundOptionRow(
                    icon: "banknote",
                    iconColor: .green,
                    title: "Cash",
                    subtitle: "Hand back cash to the customer",
                    action: {
                        onSelect(.cash)
                        dismiss()
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer(minLength: 16)
        }
    }

    private var amountText: String {
        let sym = transaction.currencyCode // fallback; caller can format
        let amt = (transaction.totalAmount as NSDecimalNumber).doubleValue
        return "\(sym) \(String(format: "%.2f", abs(amt)))"
    }
}

// MARK: - Option Row
private struct RefundOptionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
