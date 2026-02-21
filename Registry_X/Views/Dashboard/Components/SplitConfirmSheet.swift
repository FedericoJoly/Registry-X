import SwiftUI

// MARK: - Split Confirm Sheet
/// Shows all split methods with their amounts and triggers sequential payment.
struct SplitConfirmSheet: View {
    let splitEntries: [SplitEntry]
    let availableCurrencies: [Currency]
    let mainCurrencyCode: String
    let totalAmount: Decimal
    /// Number of leading entries already captured — shown greyed-out with a checkmark.
    var paidCount: Int = 0

    let onCancel: () -> Void
    let onPay: () -> Void

    // MARK: - Helpers
    private func symbol(for code: String) -> String {
        availableCurrencies.first(where: { $0.code == code })?.symbol ?? code
    }

    private func displayAmount(for entry: SplitEntry) -> Decimal {
        guard entry.currencyCode != mainCurrencyCode else { return entry.amountInMain }
        let rate = availableCurrencies.first(where: { $0.code == entry.currencyCode })?.rate ?? 1
        return entry.amountInMain * rate
    }

    private func icon(for entry: SplitEntry) -> String { entry.methodIcon }

    private func color(for entry: SplitEntry) -> Color {
        // Look up method option by name to get color
        Color.blue // fallback; entries carry icon, not color hex
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    Text("Review Split Payment")
                        .font(.title3)
                        .bold()
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(splitEntries.enumerated()), id: \.offset) { idx, entry in
                            entryRow(entry: entry, index: idx + 1)
                            if idx < splitEntries.count - 1 {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)

                    // Total row
                    HStack {
                        Text("Total")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(symbol(for: mainCurrencyCode) + totalAmount.formatted(.number.precision(.fractionLength(2))))
                            .font(.headline)
                            .bold()
                    }
                    .padding(.horizontal, 4)
                }
                .padding()

                Spacer()

                Text("Payment will be attempted in order.\nCard / QR payments require Tap to Pay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Confirm Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pay") { onPay() }
                        .bold()
                        .tint(.green)
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(entry: SplitEntry, index: Int) -> some View {
        let isPaid = index <= paidCount
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPaid ? Color.gray.opacity(0.35) : Color(hex: entry.colorHex))
                    .frame(width: 44, height: 44)
                Image(systemName: entry.methodIcon)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(isPaid ? 0.6 : 1))
                if splitEntries.filter({ $0.methodIcon == entry.methodIcon && $0.method == entry.method }).count > 1 {
                    if isPaid {
                        // Checkmark badge for paid entries
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.green))
                            .offset(x: 14, y: -14)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.orange))
                            .offset(x: 14, y: -14)
                    }
                } else if isPaid {
                    // Checkmark for unique-method paid entries too
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.green))
                        .offset(x: 14, y: -14)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isPaid ? entry.method + " — Paid" : entry.method)
                    .font(.body)
                    .foregroundStyle(isPaid ? .secondary : .primary)
                Text(entry.currencyCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(symbol(for: entry.currencyCode) + displayAmount(for: entry).formatted(.number.precision(.fractionLength(2))))
                .font(.body)
                .bold()
                .foregroundStyle(isPaid ? .secondary : .primary)
                .strikethrough(isPaid, color: .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .opacity(isPaid ? 0.65 : 1)
    }
}
