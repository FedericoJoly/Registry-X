import SwiftUI

// MARK: - Split Confirm Sheet
/// Shows the two split methods with their converted amounts and triggers payment.
struct SplitConfirmSheet: View {
    // The two methods and their amounts (in main currency), plus the selected charge currency
    let method1: PaymentMethodOption
    let amount1InMain: Decimal       // entered amount in main currency
    let currencyCode1: String        // currency to charge method1 in

    let method2: PaymentMethodOption
    let amount2InMain: Decimal
    let currencyCode2: String

    let availableCurrencies: [Currency]
    let mainCurrencyCode: String
    let totalAmount: Decimal         // full cart total in main currency

    let onCancel: () -> Void
    let onPay: () -> Void

    // MARK: - Helpers
    private func symbol(for code: String) -> String {
        availableCurrencies.first(where: { $0.code == code })?.symbol ?? code
    }

    /// Convert an amount in main currency → target currency using stored exchange rates.
    /// Rate convention: currency.rate = how many units of this currency per 1 main-currency unit.
    private func convertToDisplay(mainAmount: Decimal, targetCode: String) -> Decimal {
        guard targetCode != mainCurrencyCode else { return mainAmount }
        let targetRate = availableCurrencies.first(where: { $0.code == targetCode })?.rate ?? 1
        // mainAmount / mainRate * targetRate — but mainRate is 1 by convention
        // rate = foreign per 1 main, so: foreignAmount = mainAmount * rate
        return mainAmount * targetRate
    }

    private var displayAmount1: Decimal { convertToDisplay(mainAmount: amount1InMain, targetCode: currencyCode1) }
    private var displayAmount2: Decimal { convertToDisplay(mainAmount: amount2InMain, targetCode: currencyCode2) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary card
                VStack(spacing: 20) {
                    Text("Review Split Payment")
                        .font(.title3)
                        .bold()
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        methodRow(method: method1, amount: displayAmount1, currencyCode: currencyCode1)
                        Divider().padding(.leading, 68)
                        methodRow(method: method2, amount: displayAmount2, currencyCode: currencyCode2)
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

                // Note
                Text("Payment will be attempted in the order listed above.\nThe more complex method is processed first.")
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
                    Button("Pay") {
                        onPay()
                    }
                    .bold()
                    .tint(.green)
                }
            }
        }
    }

    @ViewBuilder
    private func methodRow(method: PaymentMethodOption, amount: Decimal, currencyCode: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: method.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(method.color)
                .cornerRadius(10)

            Text(method.name)
                .font(.body)

            Spacer()

            Text(symbol(for: currencyCode) + amount.formatted(.number.precision(.fractionLength(2))))
                .font(.body)
                .bold()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
