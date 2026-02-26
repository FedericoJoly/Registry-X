import SwiftUI

// MARK: - Split Payment Row State
struct SplitMethodEntry: Identifiable, Equatable {
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
    let derivedTotal: Decimal          // Full cart total in mainCurrencyCode
    /// When set, the header/balance counter show amounts in this currency (e.g. the panel's charge currency).
    /// Internal balance math stays in mainCurrencyCode.
    var displayCurrencyCode: String? = nil
    /// Entries already captured mid-split — shown locked, reduce the remaining balance
    var lockedEntries: [SplitEntry] = []
    /// Intent/session IDs of captured payments — needed for Void All refunds
    var lockedIntentIds: [String] = []
    let onCancel: () -> Void
    /// Called on OK with the fully-formed split entries (NOT including locked ones — those are already done)
    let onConfirm: ([SplitEntry]) -> Void
    /// Called when merchant taps Void All — refunds locked payments and closes
    var onVoidAll: (() -> Void)? = nil

    @State private var entries: [SplitMethodEntry] = []
    @State private var showingChargeCurrencyWarning = false
    @FocusState private var focusedRowId: UUID?
    /// Debounced copy of displayEnteredTotal — only updates 2s after typing stops
    @State private var debouncedEnteredTotal: Decimal = 0
    @State private var debounceTask: Task<Void, Never>? = nil

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

    /// Multiplier to convert a mainCurrencyCode amount to displayCurrencyCode for header display only.
    private var displayRate: Decimal {
        guard let dc = displayCurrencyCode, dc != mainCurrencyCode else { return 1 }
        return availableCurrencies.first(where: { $0.code == dc })?.rate ?? 1
    }
    private var effectiveDisplayCode: String { displayCurrencyCode ?? mainCurrencyCode }

    private func convert(_ amount: Decimal, from fromCode: String, to toCode: String) -> Decimal {
        guard fromCode != toCode else { return amount }
        let rateFrom = rate(for: fromCode)
        guard rateFrom > 0 else { return amount }
        return (amount / rateFrom) * rate(for: toCode)
    }

    /// Parse a locale-formatted decimal string robustly.
    /// Handles both 1.000,00 (EU) and 1,000.00 (US) thousands separators.
    private func parseDecimal(_ text: String) -> Decimal? {
        // Count occurrences of '.' and ','
        let dots = text.filter { $0 == "." }.count
        let commas = text.filter { $0 == "," }.count
        var normalized = text
        if dots > 1 {
            // Multiple dots → thousands separator, remove them
            normalized = text.replacingOccurrences(of: ".", with: "")
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        } else if commas > 1 {
            // Multiple commas → thousands separator, remove them
            normalized = text.replacingOccurrences(of: ",", with: "")
        } else if dots == 1 && commas == 1 {
            // Both present: whichever comes last is the decimal separator
            let dotIdx = text.lastIndex(of: ".")!
            let commaIdx = text.lastIndex(of: ",")!
            if commaIdx > dotIdx {
                // EU: 1.234,56 → remove dot, replace comma
                normalized = text.replacingOccurrences(of: ".", with: "")
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            } else {
                // US: 1,234.56 → remove comma
                normalized = text.replacingOccurrences(of: ",", with: "")
            }
        } else {
            // Single separator or none — just treat comma as decimal
            normalized = text.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: normalized)
    }

    private func amountInMain(_ entry: SplitMethodEntry) -> Decimal {
        guard let val = parseDecimal(entry.amountText), val > 0
        else { return 0 }
        // No button tapped → treat input as the charge currency (effectiveDisplayCode)
        let code = availableCurrencies.first(where: { $0.id == entry.selectedCurrencyId })?.code
                   ?? effectiveDisplayCode
        let r = rate(for: code)
        return r > 0 ? val / r : val
    }

    // Remaining balance after locked entries (this is what the editable rows must sum to)
    private var remainingTotal: Decimal {
        derivedTotal - lockedEntries.reduce(Decimal(0)) { $0 + $1.amountInMain }
    }

    private var enteredTotal: Decimal {
        entries.reduce(Decimal(0)) { $0 + amountInMain($1) }
    }

    /// Like amountInMain but always returns a value — drives the live "remaining" counter
    /// so it ticks as the user types before they've tapped a currency button.
    private func amountInMainForDisplay(_ entry: SplitMethodEntry) -> Decimal {
        guard let val = parseDecimal(entry.amountText), val > 0 else { return 0 }
        let code = availableCurrencies.first(where: { $0.id == entry.selectedCurrencyId })?.code
                   ?? effectiveDisplayCode
        let r = rate(for: code)
        return r > 0 ? val / r : val
    }
    private var displayEnteredTotal: Decimal {
        entries.reduce(Decimal(0)) { $0 + amountInMainForDisplay($1) }
    }

    /// Fires debounce: cancels any pending update, schedules a new one after 2 s of inactivity.
    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedEnteredTotal = displayEnteredTotal
            }
        }
    }

    private var remaining: Decimal { remainingTotal - enteredTotal }
    private var isBalanced: Bool {
        let diff = enteredTotal - remainingTotal
        return diff >= -0.005 && diff <= 0.005
    }

    private var filledEntries: [SplitMethodEntry] {
        // An entry is filled if it has a positive amount; currency defaults to effectiveDisplayCode if nil
        entries.filter { amountInMain($0) > 0 }
    }

    private var canConfirm: Bool {
        guard isBalanced else { return false }
        // Need ≥2 entries total (locked + editable)
        let totalEntries = lockedEntries.count + filledEntries.count
        return totalEntries >= 2
    }

    /// True when a non-main charge currency is set but every filled row has been
    /// explicitly switched away from it (none use it implicitly or explicitly).
    private var noEntriesUseChargeCurrency: Bool {
        guard let dc = displayCurrencyCode else { return false }  // only relevant when charge ≠ main
        let chargeCurrencyId = availableCurrencies.first(where: { $0.code == dc })?.id
        // A row uses the charge currency if: selectedCurrencyId == chargeId OR selectedCurrencyId == nil (implicit)
        return !filledEntries.contains { entry in
            entry.selectedCurrencyId == nil || entry.selectedCurrencyId == chargeCurrencyId
        }
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
            guard let rawVal = parseDecimal(entry.amountText), rawVal > 0
            else { return nil }
            // Use the explicitly-selected currency, or fall back to the charge currency
            let currencyCode = availableCurrencies.first(where: { $0.id == entry.selectedCurrencyId })?.code
                               ?? effectiveDisplayCode
            let aInMain = amountInMain(entry)
            return SplitEntry(
                method: entry.method.name,
                methodIcon: entry.method.icon,
                colorHex: entry.method.colorHex,
                amountInMain: aInMain,
                chargeAmount: rawVal,
                currencyCode: currencyCode
            )
        }
    }

    /// Extracted to help the Swift type-checker cope with the large VStack body.
    @ViewBuilder private var debouncedRemainingRow: some View {
        let displayRemaining: Decimal = (remainingTotal - debouncedEnteredTotal) * displayRate
        if debouncedEnteredTotal > 0 {
            Text("\(symbol(for: effectiveDisplayCode))\(abs(displayRemaining).formatted(.number.precision(.fractionLength(2)))) \(displayRemaining > 0 ? "remaining" : "over")")
                .font(.footnote)
                .foregroundStyle(abs(displayRemaining) < 0.01 ? .green : .red)
        }
    }

    /// Extracted header to help the Swift type-checker cope with the large body.
    @ViewBuilder private var headerView: some View {
        VStack(spacing: 4) {
            if !lockedEntries.isEmpty {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(symbol(for: effectiveDisplayCode) + (derivedTotal * displayRate).formatted(.number.precision(.fractionLength(2))))
                            .font(.headline.bold())
                    }
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    VStack(spacing: 2) {
                        Text("Remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(symbol(for: effectiveDisplayCode) + (remainingTotal * displayRate).formatted(.number.precision(.fractionLength(2))))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(isBalanced ? .green : .orange)
                    }
                }
            } else {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(symbol(for: effectiveDisplayCode) + (derivedTotal * displayRate).formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(isBalanced ? .green : .primary)
            }
            // Remaining counter — updates 2 s after typing stops
            debouncedRemainingRow
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder private var entriesListView: some View {
        List {
            // ── Locked / already-captured entries ──────────────────────────
            if !lockedEntries.isEmpty {
                Section {
                    ForEach(lockedEntries) { locked in
                        HStack(spacing: 12) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: locked.methodIcon)
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color(hex: locked.colorHex))
                                    .cornerRadius(8)
                                    .opacity(0.6)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.green)
                                    .background(Circle().fill(.white).padding(-1))
                                    .offset(x: 4, y: -4)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(locked.method)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                Text("Captured")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            let sym = availableCurrencies.first(where: { $0.code == locked.currencyCode })?.symbol ?? locked.currencyCode
                            Text(sym + locked.chargeAmount.formatted(.number.precision(.fractionLength(2))))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(UIColor.systemFill).opacity(0.3))
                    }
                } header: {
                    Text("Already Captured")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .textCase(nil)
                }
            }

            // ── Editable remaining entries ───────────────────────────────
            Section {
                ForEach($entries) { $entry in
                    SplitMethodRow(
                        entry: $entry,
                        availableCurrencies: availableCurrencies,
                        mainCurrencyCode: mainCurrencyCode,
                        implicitCurrencyCode: effectiveDisplayCode,
                        canDuplicate: canDuplicate(entry),
                        isCurrencyEnabled: { currency in
                            if entry.method.enabledCurrencies.isEmpty { return true }
                            if entry.method.enabledCurrencies.contains(currency.id) { return true }
                            let matchedId = availableCurrencies.first(where: { $0.code == currency.code })?.id
                            return matchedId.map { entry.method.enabledCurrencies.contains($0) } ?? false
                        },
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
        }
        .listStyle(.plain)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .padding()
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header: total + remaining (in displayCurrencyCode if set, else mainCurrencyCode)
                headerView

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

                entriesListView
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Split Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                // Void All: only shown when there are already-captured entries to unwind
                if !lockedEntries.isEmpty, let voidAll = onVoidAll {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Void All") {
                            voidAll()
                        }
                        .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if noEntriesUseChargeCurrency {
                            showingChargeCurrencyWarning = true
                        } else {
                            onConfirm(buildSplitEntries())
                        }
                    }
                    .bold()
                    .disabled(!canConfirm)
                }
            }
            .alert("Charge currency unused", isPresented: $showingChargeCurrencyWarning) {
                Button("Proceed anyway", role: .destructive) { onConfirm(buildSplitEntries()) }
                Button("Go back", role: .cancel) { }
            } message: {
                let sym = symbol(for: displayCurrencyCode ?? mainCurrencyCode)
                Text("The selected currency (\(sym)) hasn't been applied to any method — all rows were switched to other currencies. Are you sure you want to proceed?")
            }
        }
        .onAppear {
            // Leave selectedCurrencyId = nil so no currency button is highlighted.
            // The math implicitly uses effectiveDisplayCode (the panel charge currency).
            // The user explicitly taps a button only if they want a different currency,
            // at which point the amount converts automatically.
            entries = availableMethods.map { SplitMethodEntry(method: $0) }
        }
        .onChange(of: entries) { _, newEntries in
            // Reset debounced total instantly if all fields are empty
            let allEmpty = newEntries.allSatisfy { $0.amountText.isEmpty }
            if allEmpty {
                debounceTask?.cancel()
                debouncedEnteredTotal = 0
            } else {
                scheduleDebounce()
            }
        }
    }
}

// MARK: - Row per payment method
struct SplitMethodRow: View {
    @Binding var entry: SplitMethodEntry
    let availableCurrencies: [Currency]
    let mainCurrencyCode: String
    /// The charge currency implicitly assumed when no button is tapped.
    /// Must match effectiveDisplayCode from SplitPaySheet.
    let implicitCurrencyCode: String
    let canDuplicate: Bool
    let isCurrencyEnabled: (Currency) -> Bool
    let convert: (Decimal, String, String) -> Decimal
    var focusedId: FocusState<UUID?>.Binding
    let onDoubleTapIcon: () -> Void

    /// Robust decimal parser — handles EU (1.000,00) and US (1,000.00) formats.
    private func parseDecimal(_ text: String) -> Decimal? {
        let dots = text.filter { $0 == "." }.count
        let commas = text.filter { $0 == "," }.count
        var normalized = text
        if dots > 1 {
            normalized = text.replacingOccurrences(of: ".", with: "")
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        } else if commas > 1 {
            normalized = text.replacingOccurrences(of: ",", with: "")
        } else if dots == 1 && commas == 1 {
            let dotIdx = text.lastIndex(of: ".")!
            let commaIdx = text.lastIndex(of: ",")!
            if commaIdx > dotIdx {
                normalized = text.replacingOccurrences(of: ".", with: "")
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            } else {
                normalized = text.replacingOccurrences(of: ",", with: "")
            }
        } else {
            normalized = text.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: normalized)
    }

    private var hasValue: Bool {
        (parseDecimal(entry.amountText) ?? 0) > 0
    }

    private func currentCurrencyCode() -> String {
        // When no button is tapped, treat input as the charge currency, not mainCurrencyCode
        availableCurrencies.first(where: { $0.id == entry.selectedCurrencyId })?.code ?? implicitCurrencyCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Row 1: icon + name (left ~50%) | amount field (right ~50%) ──
            HStack(spacing: 10) {
                // Left half: icon + name
                HStack(spacing: 10) {
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
                        if canDuplicate {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.blue)
                                .background(Circle().fill(Color.white).padding(-1))
                                .offset(x: 4, y: -4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.method.name)
                            .font(.body)
                            .lineLimit(1)
                        if entry.isUserAdded {
                            Text("Swipe to remove")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right half: amount input field
                TextField("0.00", text: $entry.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                    .focused(focusedId, equals: entry.id)
                    .onChange(of: entry.amountText) { _, newVal in
                        let v = parseDecimal(newVal) ?? 0
                        if v == 0 { entry.selectedCurrencyId = nil }
                    }
            }

            // ── Row 2: currency buttons, right-aligned ─────────────────────
            HStack(spacing: 4) {
                Spacer()
                ForEach(availableCurrencies.filter { $0.isEnabled }, id: \.id) { currency in
                    let enabled = isCurrencyEnabled(currency) && hasValue
                    let selected = entry.selectedCurrencyId == currency.id
                    Button(action: {
                        guard enabled else { return }
                        guard !selected else { return }
                        let oldCode = currentCurrencyCode()
                        let newCode = currency.code
                        if hasValue, let oldVal = parseDecimal(entry.amountText) {
                            let newVal = convert(oldVal, oldCode, newCode)
                            let nsVal = NSDecimalNumber(decimal: newVal)
                            entry.amountText = nsVal.stringValue
                        }
                        entry.selectedCurrencyId = currency.id
                    }) {
                        Text(currency.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 28)
                            .background(selected ? Color.blue : (enabled ? Color(UIColor.systemGray5) : Color(UIColor.systemGray5).opacity(0.3)))
                            .foregroundStyle(selected ? .white : (enabled ? .primary : Color.secondary.opacity(0.4)))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 10)
    }
}
