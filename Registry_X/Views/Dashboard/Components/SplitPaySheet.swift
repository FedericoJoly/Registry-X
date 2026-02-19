import SwiftUI

// MARK: - Split Payment State
struct SplitMethodEntry: Identifiable {
    let id: UUID             // PaymentMethodOption.id
    let method: PaymentMethodOption
    var amountText: String = ""       // displayed & entered in selectedCurrency (or main if none)
    var selectedCurrencyId: UUID?     // which currency the user selected for this method
}

// MARK: - SplitPaySheet
struct SplitPaySheet: View {
    let availableMethods: [PaymentMethodOption]
    let availableCurrencies: [Currency]   // all enabled currencies on the event
    let mainCurrencyCode: String
    let derivedTotal: Decimal             // full cart total in main currency
    let onCancel: () -> Void
    // Called when OK tapped: method1, amount1InMain, currCode1, method2, amount2InMain, currCode2
    let onConfirm: (PaymentMethodOption, Decimal, String, PaymentMethodOption, Decimal, String) -> Void

    @State private var entries: [SplitMethodEntry] = []
    @FocusState private var focusedMethodId: UUID?

    // MARK: - Helpers
    private func mainSymbol() -> String { symbol(for: mainCurrencyCode) }

    private func symbol(for code: String) -> String {
        availableCurrencies.first(where: { $0.code == code })?.symbol ?? code
    }

    /// Exchange rate: 1 main → `rate` units of `code`.
    /// Convention from PanelView: currency.rate = how many of this currency per 1 main.
    private func rate(for code: String) -> Decimal {
        if code == mainCurrencyCode { return 1 }
        return availableCurrencies.first(where: { $0.code == code })?.rate ?? 1
    }

    /// Convert an amount from one currency to another via main as the pivot.
    private func convert(_ amount: Decimal, from fromCode: String, to toCode: String) -> Decimal {
        guard fromCode != toCode else { return amount }
        let rateFrom = rate(for: fromCode)   // foreign per 1 main
        let rateTo   = rate(for: toCode)
        guard rateFrom > 0 else { return amount }
        let inMain = rateFrom > 0 ? amount / rateFrom : amount   // back to main
        return inMain * rateTo
    }

    /// Amount in main currency for a given entry.
    private func amountInMain(_ entry: SplitMethodEntry) -> Decimal {
        guard let val = Decimal(string: entry.amountText.replacingOccurrences(of: ",", with: ".")),
              val > 0 else { return 0 }
        let code = availableCurrencies.first(where: { $0.id == entry.selectedCurrencyId })?.code ?? mainCurrencyCode
        let r = rate(for: code)
        return r > 0 ? val / r : val
    }

    // Sum of entered amounts converted to main currency
    private var enteredTotal: Decimal {
        entries.reduce(Decimal(0)) { acc, entry in acc + amountInMain(entry) }
    }

    private var remaining: Decimal { derivedTotal - enteredTotal }
    private var isBalanced: Bool {
        // Allow tiny floating-point epsilon
        let diff = enteredTotal - derivedTotal
        return diff >= -0.005 && diff <= 0.005
    }

    // Methods that have Stripe card (tap-to-pay)
    private func isCard(_ m: PaymentMethodOption) -> Bool {
        m.icon.contains("creditcard") && m.enabledProviders.contains("stripe")
    }
    private func isQR(_ m: PaymentMethodOption) -> Bool {
        m.icon.contains("qrcode") && m.enabledProviders.contains("stripe")
    }

    // Any card method has a value entered?
    private var cardHasValue: Bool {
        entries.contains { isCard($0.method) && (Decimal(string: $0.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0 }
    }
    // Any QR method has a value entered?
    private var qrHasValue: Bool {
        entries.contains { isQR($0.method) && (Decimal(string: $0.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0 }
    }

    // Methods with an entered value
    private var filledEntries: [SplitMethodEntry] {
        entries.filter { amountInMain($0) > 0 }
    }

    // Currency enabled for a method
    private func isCurrencyEnabled(_ currency: Currency, for method: PaymentMethodOption) -> Bool {
        method.enabledCurrencies.contains(currency.id)
    }

    // MARK: - OK validation: balanced and exactly 2 filled methods with currency selected
    private var canConfirm: Bool {
        isBalanced &&
        filledEntries.count == 2 &&
        filledEntries.allSatisfy { $0.selectedCurrencyId != nil }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Running total header
                VStack(spacing: 4) {
                    Text("Total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(mainSymbol() + derivedTotal.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(isBalanced ? .green : .primary)
                    if !isBalanced && enteredTotal > 0 {
                        Text("\(mainSymbol())\(remaining.formatted(.number.precision(.fractionLength(2)))) remaining")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGroupedBackground))

                Divider()

                // Method rows
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($entries) { $entry in
                            SplitMethodRow(
                                entry: $entry,
                                availableCurrencies: availableCurrencies,
                                mainCurrencyCode: mainCurrencyCode,
                                isDisabledDueToMutualExclusion: mutuallyExcluded(entry),
                                isCurrencyEnabled: { isCurrencyEnabled($0, for: entry.method) },
                                convert: convert,
                                focusedId: $focusedMethodId
                            )
                            Divider().padding(.leading, 20)
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)
                    .padding()
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Select Payment Methods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        guard filledEntries.count == 2 else { return }
                        let e1 = filledEntries[0]
                        let e2 = filledEntries[1]
                        // Pass main-currency amounts
                        let a1 = amountInMain(e1)
                        let a2 = amountInMain(e2)
                        let c1 = availableCurrencies.first(where: { $0.id == e1.selectedCurrencyId })?.code ?? mainCurrencyCode
                        let c2 = availableCurrencies.first(where: { $0.id == e2.selectedCurrencyId })?.code ?? mainCurrencyCode
                        onConfirm(e1.method, a1, c1, e2.method, a2, c2)
                    }
                    .bold()
                    .disabled(!canConfirm)
                }
            }
        }
        .onAppear {
            entries = availableMethods.map { SplitMethodEntry(id: $0.id, method: $0) }
        }
    }

    private func mutuallyExcluded(_ entry: SplitMethodEntry) -> Bool {
        // Card and QR are mutually exclusive
        if isCard(entry.method) && qrHasValue { return true }
        if isQR(entry.method) && cardHasValue { return true }
        return false
    }
}

// MARK: - Row per payment method
struct SplitMethodRow: View {
    @Binding var entry: SplitMethodEntry
    let availableCurrencies: [Currency]
    let mainCurrencyCode: String
    let isDisabledDueToMutualExclusion: Bool
    let isCurrencyEnabled: (Currency) -> Bool
    /// Convert amount between currency codes
    let convert: (Decimal, String, String) -> Decimal
    var focusedId: FocusState<UUID?>.Binding

    private var isRowDisabled: Bool { isDisabledDueToMutualExclusion }
    private var hasValue: Bool {
        (Decimal(string: entry.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    private func currentCurrencyCode() -> String {
        availableCurrencies.first(where: { $0.id == entry.selectedCurrencyId })?.code ?? mainCurrencyCode
    }

    var body: some View {
        HStack(spacing: 12) {
            // Method icon + name
            Image(systemName: entry.method.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(isRowDisabled ? Color.gray : entry.method.color)
                .cornerRadius(8)

            Text(entry.method.name)
                .font(.body)
                .foregroundStyle(isRowDisabled ? .secondary : .primary)
                .frame(minWidth: 80, alignment: .leading)

            Spacer()

            // Amount field
            TextField("0.00", text: $entry.amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
                .focused(focusedId, equals: entry.id)
                .disabled(isRowDisabled)
                .opacity(isRowDisabled ? 0.4 : 1)
                // Auto-clear if row becomes disabled
                .onChange(of: isRowDisabled) { _, disabled in
                    if disabled { entry.amountText = ""; entry.selectedCurrencyId = nil }
                }
                // Auto-clear selectedCurrencyId when amount is cleared
                .onChange(of: entry.amountText) { _, newVal in
                    let v = Decimal(string: newVal.replacingOccurrences(of: ",", with: ".")) ?? 0
                    if v == 0 { entry.selectedCurrencyId = nil }
                }

            // Currency symbol buttons — only enabled after a value is entered
            HStack(spacing: 4) {
                ForEach(availableCurrencies.filter { $0.isEnabled }, id: \.id) { currency in
                    let enabled = isCurrencyEnabled(currency) && !isRowDisabled && hasValue
                    let selected = entry.selectedCurrencyId == currency.id
                    Button(action: {
                        guard enabled else { return }
                        if selected {
                            entry.selectedCurrencyId = nil
                        } else {
                            // Convert existing amount from old currency to new currency
                            let oldCode = currentCurrencyCode()
                            let newCode = currency.code
                            if hasValue, let oldVal = Decimal(string: entry.amountText.replacingOccurrences(of: ",", with: ".")) {
                                let newVal = convert(oldVal, oldCode, newCode)
                                entry.amountText = newVal.formatted(.number.precision(.fractionLength(2)))
                            }
                            entry.selectedCurrencyId = currency.id
                        }
                    }) {
                        Text(currency.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(selected ? Color.blue : (enabled ? Color(UIColor.systemGray5) : Color(UIColor.systemGray5).opacity(0.3)))
                            .foregroundStyle(selected ? .white : (enabled ? .primary : Color.secondary.opacity(0.3)))
                            .cornerRadius(6)
                    }
                    .disabled(!enabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.15), value: isRowDisabled)
    }
}
