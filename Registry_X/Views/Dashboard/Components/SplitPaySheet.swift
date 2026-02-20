import SwiftUI

// MARK: - Split Payment Row State
struct SplitMethodEntry: Identifiable {
    let id: UUID = UUID()                   // unique row id (NOT the method option id)
    let method: PaymentMethodOption
    var amountText: String = ""
    var selectedCurrencyId: UUID?
    var isUserAdded: Bool = false            // true = inserted via double-tap (can be removed)
}

// MARK: - SplitPaySheet
struct SplitPaySheet: View {
    let availableMethods: [PaymentMethodOption]
    let availableCurrencies: [Currency]
    let mainCurrencyCode: String
    let derivedTotal: Decimal
    let onCancel: () -> Void
    /// Called on OK with the fully-formed split entries
    let onConfirm: ([SplitEntry]) -> Void

    @State private var entries: [SplitMethodEntry] = []
    @FocusState private var focusedRowId: UUID?

    // MARK: - Caps
    private let maxTotalRows = 6
    private let maxRowsPerMethod = 3

    // MARK: - Helpers
    private func symbol(for code: String) -> String {
        availableCurrencies.first(where: { $0.code == code })?.symbol ?? code
    }

    private func rate(for code: String) -> Decimal {
        if code == mainCurrencyCode { return 1 }
        return availableCurrencies.first(where: { $0.code == code })?.rate ?? 1
    }

    private func convert(_ amount: Decimal, from fromCode: String, to toCode: String) -> Decimal {
        guard fromCode != toCode else { return amount }
        let rateFrom = rate(for: fromCode)
        guard rateFrom > 0 else { return amount }
        return (amount / rateFrom) * rate(for: toCode)
    }

    private func amountInMain(_ entry: SplitMethodEntry) -> Decimal {
        guard let val = Decimal(string: entry.amountText.replacingOccurrences(of: ",", with: ".")),
              val > 0 else { return 0 }
        let code = availableCurrencies.first(where: { $0.id == entry.selectedCurrencyId })?.code ?? mainCurrencyCode
        let r = rate(for: code)
        return r > 0 ? val / r : val
    }

    private var enteredTotal: Decimal {
        entries.reduce(Decimal(0)) { $0 + amountInMain($1) }
    }

    private var remaining: Decimal { derivedTotal - enteredTotal }
    private var isBalanced: Bool {
        let diff = enteredTotal - derivedTotal
        return diff >= -0.005 && diff <= 0.005
    }

    private var filledEntries: [SplitMethodEntry] {
        entries.filter { amountInMain($0) > 0 && $0.selectedCurrencyId != nil }
    }

    private var canConfirm: Bool {
        isBalanced && filledEntries.count >= 2
    }

    // How many rows already exist for a given method option id
    private func rowCount(for optionId: UUID) -> Int {
        entries.filter { $0.method.id == optionId }.count
    }

    // Can we insert another row for this method?
    private func canDuplicate(_ entry: SplitMethodEntry) -> Bool {
        entries.count < maxTotalRows &&
        rowCount(for: entry.method.id) < maxRowsPerMethod
    }

    // Insert a duplicate row of the same method immediately after the given row
    private func insertRow(after entry: SplitMethodEntry) {
        guard canDuplicate(entry) else { return }
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var newRow = SplitMethodEntry(method: entry.method)
        newRow.isUserAdded = true
        withAnimation(.easeInOut(duration: 0.2)) {
            entries.insert(newRow, at: idx + 1)
        }
    }

    // MARK: - Build SplitEntry array for callback
    private func buildSplitEntries() -> [SplitEntry] {
        filledEntries.compactMap { entry in
            guard let currId = entry.selectedCurrencyId,
                  let currency = availableCurrencies.first(where: { $0.id == currId }),
                  let rawVal = Decimal(string: entry.amountText.replacingOccurrences(of: ",", with: ".")),
                  rawVal > 0
            else { return nil }
            let aInMain = amountInMain(entry)
            return SplitEntry(
                method: entry.method.name,
                methodIcon: entry.method.icon,
                amountInMain: aInMain,
                chargeAmount: rawVal,
                currencyCode: currency.code
            )
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header: total + remaining
                VStack(spacing: 4) {
                    Text("Total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(symbol(for: mainCurrencyCode) + derivedTotal.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(isBalanced ? .green : .primary)
                    if !isBalanced && enteredTotal > 0 {
                        Text("\(symbol(for: mainCurrencyCode))\(abs(remaining).formatted(.number.precision(.fractionLength(2)))) \(remaining > 0 ? "remaining" : "over")")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGroupedBackground))

                Divider()

                // Hint for double-tap
                HStack {
                    Image(systemName: "hand.tap")
                        .font(.caption)
                    Text("Double-tap an icon to add another row of the same method (max 3)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.systemGroupedBackground))

                Divider()

                List {
                    ForEach($entries) { $entry in
                        SplitMethodRow(
                            entry: $entry,
                            availableCurrencies: availableCurrencies,
                            mainCurrencyCode: mainCurrencyCode,
                            canDuplicate: canDuplicate(entry),
                            isCurrencyEnabled: { entry.method.enabledCurrencies.contains($0.id) },
                            convert: convert,
                            focusedId: $focusedRowId,
                            onDoubleTapIcon: { insertRow(after: entry) }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(UIColor.systemBackground))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if entry.isUserAdded {
                                Button(role: .destructive) {
                                    withAnimation {
                                        entries.removeAll { $0.id == entry.id }
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Split Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onConfirm(buildSplitEntries())
                    }
                    .bold()
                    .disabled(!canConfirm)
                }
            }
        }
        .onAppear {
            entries = availableMethods.map { SplitMethodEntry(method: $0) }
        }
    }
}

// MARK: - Row per payment method
struct SplitMethodRow: View {
    @Binding var entry: SplitMethodEntry
    let availableCurrencies: [Currency]
    let mainCurrencyCode: String
    let canDuplicate: Bool
    let isCurrencyEnabled: (Currency) -> Bool
    let convert: (Decimal, String, String) -> Decimal
    var focusedId: FocusState<UUID?>.Binding
    let onDoubleTapIcon: () -> Void

    private var hasValue: Bool {
        (Decimal(string: entry.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    private func currentCurrencyCode() -> String {
        availableCurrencies.first(where: { $0.id == entry.selectedCurrencyId })?.code ?? mainCurrencyCode
    }

    var body: some View {
        HStack(spacing: 12) {
            // Method icon — double-tap to duplicate
            ZStack(alignment: .topTrailing) {
                Image(systemName: entry.method.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(entry.method.color)
                    .cornerRadius(8)
                    .onTapGesture(count: 2) {
                        onDoubleTapIcon()
                    }

                // Badge if duplication is available
                if canDuplicate {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                        .background(Circle().fill(Color.white).padding(-1))
                        .offset(x: 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.method.name)
                    .font(.body)
                if entry.isUserAdded {
                    Text("Swipe to remove")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
                .onChange(of: entry.amountText) { _, newVal in
                    let v = Decimal(string: newVal.replacingOccurrences(of: ",", with: ".")) ?? 0
                    if v == 0 { entry.selectedCurrencyId = nil }
                }

            // Currency buttons
            HStack(spacing: 4) {
                ForEach(availableCurrencies.filter { $0.isEnabled }, id: \.id) { currency in
                    let enabled = isCurrencyEnabled(currency) && hasValue
                    let selected = entry.selectedCurrencyId == currency.id
                    Button(action: {
                        guard enabled else { return }
                        if selected {
                            entry.selectedCurrencyId = nil
                        } else {
                            let oldCode = currentCurrencyCode()
                            let newCode = currency.code
                            if hasValue,
                               let oldVal = Decimal(string: entry.amountText.replacingOccurrences(of: ",", with: ".")) {
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
                            .foregroundStyle(selected ? .white : (enabled ? .primary : Color.secondary.opacity(0.4)))
                            .cornerRadius(6)
                    }
                    .disabled(!enabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
