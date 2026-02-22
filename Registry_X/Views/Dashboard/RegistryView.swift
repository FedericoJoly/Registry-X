import SwiftUI
import SwiftData

struct RegistryView: View {
    @Bindable var event: Event
    var onQuit: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    
    // Date navigation state
    @State private var selectedDate: Date = Date()
    @State private var transactionToDelete: Transaction?
    @State private var showingDeleteConfirmation = false
    @State private var selectedTab: RegistryTab = .transactions
    
    enum RegistryTab: Int, CaseIterable {
        case transactions
        case currencies
        case products
        case groups

        var title: String {
            switch self {
            case .transactions: return "Transactions"
            case .currencies:   return "Currencies"
            case .products:     return "Products"
            case .groups:       return "Groups"
            }
        }
    }
    
    // Normalize date to start of day
    private var selectedDayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }
    
    private var selectedDayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: selectedDayStart) ?? selectedDayStart
    }
    
    // Transactions for selected day, sorted so refund cards appear directly above their original
    private var dayTransactions: [Transaction] {
        let txns = event.transactions.filter { transaction in
            transaction.timestamp >= selectedDayStart && transaction.timestamp < selectedDayEnd
        }.sorted { $0.timestamp > $1.timestamp }

        // Re-sort: for each refund tx, insert it immediately before its linked original
        var result: [Transaction] = []
        var inserted = Set<UUID>()
        for tx in txns {
            guard !inserted.contains(tx.id) else { continue }
            // If this is a refund, it'll be pulled when its original is processed
            if tx.isRefund { continue }
            // Insert any refund linked to this transaction first
            let refunds = txns.filter { $0.isRefund && $0.refundedTransactionId == tx.id }
            for refund in refunds {
                result.append(refund)
                inserted.insert(refund.id)
            }
            result.append(tx)
            inserted.insert(tx.id)
        }
        // Append any orphaned refund txns at the top
        let orphans = txns.filter { $0.isRefund && !inserted.contains($0.id) }
        return orphans + result
    }
    
    // Daily summary
    private var dailyTotal: Decimal {
        dayTransactions.reduce(0) { $0 + convertToMainCurrency($1.totalAmount, from: $1.currencyCode) }
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    private var mainCurrencySymbol: String {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        return mainCurrency?.symbol ?? "$"
    }
    
    // Check if there are any transactions before selected date
    private var hasEarlierTransactions: Bool {
        event.transactions.contains { $0.timestamp < selectedDayStart }
    }

    // MARK: - Day Currency Breakdown (mirrors TotalsView.groupedByCurrency but day-scoped)
    private var groupedByCurrencyForDay: [TotalsView.CurrencyGroup] {
        var currencyDict: [String: [(method: String, quantity: Decimal, subtotal: Decimal)]] = [:]
        for transaction in dayTransactions {
            let totalQty = Decimal(transaction.lineItems.reduce(0) { $0 + $1.quantity })
            if transaction.isNWaySplit {
                let entries = transaction.splitEntries
                let entryTotal = entries.reduce(Decimal(0)) { $0 + $1.amountInMain }
                for entry in entries {
                    let ratio = entryTotal > 0 ? entry.amountInMain / entryTotal : (Decimal(1) / Decimal(entries.count))
                    if currencyDict[transaction.currencyCode] == nil { currencyDict[transaction.currencyCode] = [] }
                    currencyDict[transaction.currencyCode]!.append((method: entry.method, quantity: totalQty * ratio, subtotal: entry.amountInMain))
                }
            } else {
                let methodName = registryPaymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
                if currencyDict[transaction.currencyCode] == nil { currencyDict[transaction.currencyCode] = [] }
                currencyDict[transaction.currencyCode]!.append((method: methodName, quantity: totalQty, subtotal: transaction.totalAmount))
            }
        }
        var result: [TotalsView.CurrencyGroup] = []
        for (code, txns) in currencyDict {
            var methodDict: [String: (units: Decimal, subtotal: Decimal)] = [:]
            var total = Decimal(0)
            for t in txns {
                total += t.subtotal
                if let ex = methodDict[t.method] { methodDict[t.method] = (ex.units + t.quantity, ex.subtotal + t.subtotal) }
                else { methodDict[t.method] = (t.quantity, t.subtotal) }
            }
            let pms = methodDict.map { TotalsView.PaymentMethodRow(methodName: $0.key, units: $0.value.units, subtotal: $0.value.subtotal) }.sorted { $0.methodName < $1.methodName }
            let sym = event.currencies.first(where: { $0.code == code })?.symbol ?? code
            result.append(TotalsView.CurrencyGroup(currencyCode: code, currencySymbol: sym, total: total, paymentMethods: pms))
        }
        return result.sorted { $0.currencyCode < $1.currencyCode }
    }

    private func registryPaymentMethodName(_ method: PaymentMethod, icon: String? = nil) -> String {
        if let icon = icon {
            if icon.contains("phone") { return "Bizum" }
            if icon.contains("qrcode") { return "QR" }
        }
        switch method {
        case .cash: return "Cash"
        case .card: return "Card"
        case .transfer: return "Transfer"
        case .other: return "QR"
        }
    }
    
    // MARK: - Groups Data Structures
    struct CategoryGroup: Identifiable {
        let id = UUID()
        let category: Category
        let totalUnits: Int
        let total: Decimal
        let currencySections: [CurrencySection]
    }
    
    struct CurrencySection: Identifiable {
        let id = UUID()
        let currencyCode: String
        let currencySymbol: String
        let paymentMethods: [PaymentMethodRow]
    }
    
    struct PaymentMethodRow: Identifiable {
        let id = UUID()
        let methodName: String
        let units: Decimal   // may be fractional for split transactions
        let subtotal: Decimal
    }
    
    struct SubgroupGroup: Identifiable {
        let id = UUID()
        let subgroupName: String
        let category: Category?
        let totalUnits: Int
        let total: Decimal
        let products: [ProductRow]
    }
    
    struct ProductRow: Identifiable {
        let id = UUID()
        let productName: String
        let units: Int
        let subtotal: Decimal
    }
    
    struct ProductGroup: Identifiable {
        let id = UUID()
        let productName: String
        let category: Category?
        let totalUnits: Int
        let total: Decimal
        let currencySections: [CurrencySection]
    }
    
    // MARK: - Grouped Data
    private var groupedByCategory: [CategoryGroup] {
        var categoryDict: [UUID: (category: Category, items: [(item: LineItem, currencyCode: String)])] = [:]
        
        // Collect all line items grouped by category
        for transaction in dayTransactions {
            for item in transaction.lineItems {
                // ALWAYS look up by name to avoid invalidated SwiftData references
                // Include deleted products (transaction data is sacred)
                let product = event.products.first(where: { 
                    $0.name == item.productName
                })
                let category = product?.category
                
                if let category = category {
                    if categoryDict[category.id] == nil {
                        categoryDict[category.id] = (category, [])
                    }
                    categoryDict[category.id]?.items.append((item, transaction.currencyCode))
                }
            }
        }
        
        // Build CategoryGroup for each category
        var result: [CategoryGroup] = []
        for (_, value) in categoryDict {
            let (category, items) = value
            
            // Group by currency and payment method using tuples
            var currencyDict: [String: [(method: String, quantity: Decimal, subtotal: Decimal)]] = [:]
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0
            
            for (item, currencyCode) in items {
                // Convert to main currency for total
                let subtotalInMain = convertToMainCurrency(item.subtotal, from: currencyCode)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
                
                // Find transaction for this item to get payment method
                if let transaction = dayTransactions.first(where: { $0.lineItems.contains(where: { $0.id == item.id }) }) {
                    if transaction.isNWaySplit {
                        let entries = transaction.splitEntries
                        let entryTotal = entries.reduce(Decimal(0)) { $0 + $1.amountInMain }
                        var remaining = item.subtotal
                        for (i, entry) in entries.enumerated() {
                            let ratio = entryTotal > 0 ? entry.amountInMain / entryTotal : (Decimal(1) / Decimal(entries.count))
                            let share: Decimal
                            if i == entries.count - 1 {
                                share = remaining
                            } else {
                                let rounded = NSDecimalNumber(decimal: item.subtotal * ratio)
                                    .rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).decimalValue
                                share = rounded
                                remaining -= rounded
                            }
                            if share > 0 {
                                let qtyShare = NSDecimalNumber(decimal: Decimal(item.quantity) * ratio)
                                    .rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).decimalValue
                                if currencyDict[currencyCode] == nil { currencyDict[currencyCode] = [] }
                                currencyDict[currencyCode]!.append((method: entry.method, quantity: qtyShare, subtotal: share))
                            }
                        }
                    } else {
                        let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
                        if currencyDict[currencyCode] == nil { currencyDict[currencyCode] = [] }
                        currencyDict[currencyCode]!.append((method: methodName, quantity: Decimal(item.quantity), subtotal: item.subtotal))
                    }
                }
            }
            
            // Convert to CurrencySections with aggregated payment methods
            var currencySections: [CurrencySection] = []
            for (code, transactions) in currencyDict {
                // Aggregate by method
                var methodDict: [String: (units: Decimal, subtotal: Decimal)] = [:]
                for trans in transactions {
                    if let existing = methodDict[trans.method] {
                        methodDict[trans.method] = (existing.units + trans.quantity, existing.subtotal + trans.subtotal)
                    } else {
                        methodDict[trans.method] = (trans.quantity, trans.subtotal)
                    }
                }
                
                let paymentMethods = methodDict.map { (method, value) in
                    PaymentMethodRow(methodName: method, units: value.units, subtotal: value.subtotal)
                }
                
                currencySections.append(CurrencySection(
                    currencyCode: code,
                    currencySymbol: currencySymbol(for: code),
                    paymentMethods: paymentMethods
                ))
            }
            
            let sortedSections = currencySections.sorted { $0.currencyCode < $1.currencyCode }
            
            result.append(CategoryGroup(
                category: category,
                totalUnits: totalUnits,
                total: totalInMainCurrency,
                currencySections: sortedSections
            ))
        }
        
        return result.sorted { $0.category.sortOrder < $1.category.sortOrder }
    }
    
    private var groupedBySubgroup: [SubgroupGroup] {
        var subgroupDict: [String: (category: Category?, items: [(item: LineItem, currencyCode: String)])] = [:]
        
        // Collect all line items grouped by subgroup
        for transaction in dayTransactions {
            for item in transaction.lineItems {
                if let subgroup = item.subgroup, !subgroup.isEmpty {
                    if subgroupDict[subgroup] == nil {
                        // ALWAYS look up by name to avoid invalidated SwiftData references
                        // Include deleted products (transaction data is sacred)
                        let product = event.products.first(where: { 
                            $0.name == item.productName
                        })
                        subgroupDict[subgroup] = (product?.category, [])
                    }
                    subgroupDict[subgroup]?.items.append((item, transaction.currencyCode))
                }
            }
        }
        
        // Build SubgroupGroup for each subgroup
        return subgroupDict.map { (subgroupName, value) in
            let (category, items) = value
            
            // Group by product name
            var productDict: [String: (quantity: Int, subtotal: Decimal)] = [:]
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0
            
            for (item, currencyCode) in items {
                // Convert to main currency for total
                let subtotalInMain = convertToMainCurrency(item.subtotal, from: currencyCode)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
                
                // Accumulate per-product subtotals in main currency (same conversion as the header total)
                if let existing = productDict[item.productName] {
                    productDict[item.productName] = (existing.quantity + item.quantity, existing.subtotal + subtotalInMain)
                } else {
                    productDict[item.productName] = (item.quantity, subtotalInMain)
                }
            }
            
            let products = productDict.map { (name, value) in
                ProductRow(productName: name, units: value.quantity, subtotal: value.subtotal)
            }.sorted { prod1, prod2 in
                // Get products from event to access sortOrder
                guard let p1 = event.products.first(where: { $0.name == prod1.productName }),
                      let p2 = event.products.first(where: { $0.name == prod2.productName }) else {
                    return prod1.productName < prod2.productName
                }
                return p1.sortOrder < p2.sortOrder
            }
            
            return SubgroupGroup(
                subgroupName: subgroupName,
                category: category,
                totalUnits: totalUnits,
                total: totalInMainCurrency,
                products: products
            )
        }.sorted { $0.subgroupName < $1.subgroupName }
    }
    
    private var groupedByProduct: [ProductGroup] {
        var productDict: [String: (category: Category?, items: [(item: LineItem, currencyCode: String)])] = [:]
        
        // Collect all line items grouped by product name
        for transaction in dayTransactions {
            for item in transaction.lineItems {
                if productDict[item.productName] == nil {
                    // ALWAYS look up by name to avoid invalidated SwiftData references
                    // Include deleted products (transaction data is sacred)
                    let product = event.products.first(where: { 
                        $0.name == item.productName
                    })
                    productDict[item.productName] = (product?.category, [])
                }
                productDict[item.productName]?.items.append((item, transaction.currencyCode))
            }
        }
        
        // Build ProductGroup for each product
        var result: [ProductGroup] = []
        for (productName, value) in productDict {
            let (category, items) = value
            
            // Group by currency and payment method
            var currencyDict: [String: [(method: String, quantity: Decimal, subtotal: Decimal)]] = [:]
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0
            
            for (item, currencyCode) in items {
                // Convert to main currency for total
                let subtotalInMain = convertToMainCurrency(item.subtotal, from: currencyCode)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
                
                // Find transaction for this item to get payment method
                if let transaction = dayTransactions.first(where: { $0.lineItems.contains(where: { $0.id == item.id }) }) {
                    if transaction.isNWaySplit {
                        let entries = transaction.splitEntries
                        let entryTotal = entries.reduce(Decimal(0)) { $0 + $1.amountInMain }
                        var remaining = item.subtotal
                        for (i, entry) in entries.enumerated() {
                            let ratio = entryTotal > 0 ? entry.amountInMain / entryTotal : (Decimal(1) / Decimal(entries.count))
                            let share: Decimal
                            if i == entries.count - 1 {
                                share = remaining
                            } else {
                                let rounded = NSDecimalNumber(decimal: item.subtotal * ratio)
                                    .rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).decimalValue
                                share = rounded
                                remaining -= rounded
                            }
                            if share > 0 {
                                let qtyShare = NSDecimalNumber(decimal: Decimal(item.quantity) * ratio)
                                    .rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).decimalValue
                                if currencyDict[currencyCode] == nil { currencyDict[currencyCode] = [] }
                                currencyDict[currencyCode]!.append((method: entry.method, quantity: qtyShare, subtotal: share))
                            }
                        }
                    } else {
                        let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
                        if currencyDict[currencyCode] == nil { currencyDict[currencyCode] = [] }
                        currencyDict[currencyCode]!.append((method: methodName, quantity: Decimal(item.quantity), subtotal: item.subtotal))
                    }
                }
            }
            
            // Convert to CurrencySections with aggregated payment methods
            var currencySections: [CurrencySection] = []
            for (code, transactions) in currencyDict {
                // Aggregate by method
                var methodDict: [String: (units: Decimal, subtotal: Decimal)] = [:]
                for trans in transactions {
                    if let existing = methodDict[trans.method] {
                        methodDict[trans.method] = (existing.units + trans.quantity, existing.subtotal + trans.subtotal)
                    } else {
                        methodDict[trans.method] = (trans.quantity, trans.subtotal)
                    }
                }
                
                let paymentMethods = methodDict.map { (method, value) in
                    PaymentMethodRow(methodName: method, units: value.units, subtotal: value.subtotal)
                }
                
                currencySections.append(CurrencySection(
                    currencyCode: code,
                    currencySymbol: currencySymbol(for: code),
                    paymentMethods: paymentMethods
                ))
            }
            
            let sortedSections = currencySections.sorted { $0.currencyCode < $1.currencyCode }
            
            result.append(ProductGroup(
                productName: productName,
                category: category,
                totalUnits: totalUnits,
                total: totalInMainCurrency,
                currencySections: sortedSections
            ))
        }
        
        return result.sorted { prod1, prod2 in
            // Get products from event to access sortOrder
            guard let p1 = event.products.first(where: { $0.name == prod1.productName }),
                  let p2 = event.products.first(where: { $0.name == prod2.productName }) else {
                return prod1.productName < prod2.productName
            }
            return p1.sortOrder < p2.sortOrder
        }
    }
    
    private func paymentMethodName(_ method: PaymentMethod, icon: String? = nil) -> String {
        // Check icon first for more specific method names
        if let icon = icon {
            if icon.contains("phone") { return "Bizum" }
            if icon.contains("qrcode") { return "QR" }
        }
        
        // Fallback to enum
        switch method {
        case .cash: return "Cash"
        case .card: return "Card"
        case .transfer: return "Transfer"
        case .other: return "QR"
        }
    }
    
    private func currencySymbol(for code: String) -> String {
        return event.currencies.first(where: { $0.code == code })?.symbol ?? code
    }

    /// Format a unit count: whole numbers show as "N unit(s)", fractions show as "0.97 units"
    private func formatUnits(_ units: Decimal) -> String {
        let count = NSDecimalNumber(decimal: units).intValue
        let isWhole = Decimal(count) == units
        if isWhole {
            return count == 1 ? "1 unit" : "\(count) units"
        } else {
            return "\(units.formatted(.number.precision(.fractionLength(2)))) units"
        }
    }

    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let user = authService.currentUser {
                EventInfoHeader(event: event, userFullName: user.fullName, onQuit: onQuit)
            } else {
                EventInfoHeader(event: event, userFullName: "Operator", onQuit: onQuit)
            }
            
            // Content
            VStack(spacing: 16) {
                // Day Summary Box
                DaySummaryBox(
                    date: selectedDate,
                    isToday: isToday,
                    transactionCount: dayTransactions.count,
                    totalAmount: dailyTotal,
                    currencySymbol: mainCurrencySymbol,
                    hasEarlierTransactions: hasEarlierTransactions,
                    onPrevious: moveToPreviousDay,
                    onNext: moveToNextDay
                )
                .padding(.top)
                
                // ── Tab header: shows 3, 4th slides in on swipe ─────────────
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                ForEach(RegistryTab.allCases, id: \.self) { tab in
                                    Button(action: {
                                        withAnimation { selectedTab = tab }
                                    }) {
                                        Text(tab.title)
                                            .font(.headline)
                                            .foregroundStyle(selectedTab == tab ? .green : .secondary)
                                            .padding(.bottom, 6)
                                            .overlay(alignment: .bottom) {
                                                if selectedTab == tab {
                                                    Rectangle().fill(Color.green).frame(height: 2)
                                                }
                                            }
                                    }
                                    .frame(width: geo.size.width / 3)
                                    .id(tab)
                                }
                            }
                        }
                        .frame(height: 32)
                    }
                    .onChange(of: selectedTab) { _, newTab in
                        withAnimation {
                            proxy.scrollTo(newTab, anchor: .center)
                        }
                    }
                }
                .padding(.horizontal)

                // ── Swipeable content ─────────────────────────────────────────
                TabView(selection: Binding(
                    get: { selectedTab.rawValue },
                    set: { selectedTab = RegistryTab(rawValue: $0) ?? .transactions }
                )) {
                    // Transactions
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if dayTransactions.isEmpty {
                                ContentUnavailableView(
                                    "No Transactions",
                                    systemImage: "cart",
                                    description: Text("No sales recorded for this day")
                                )
                                .padding(.top, 60)
                            } else {
                                ForEach(dayTransactions) { transaction in
                                    TransactionCard(
                                        transaction: transaction,
                                        event: event,
                                        onDelete: {
                                            transactionToDelete = transaction
                                            showingDeleteConfirmation = true
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .tag(RegistryTab.transactions.rawValue)

                    // Currencies
                    CurrenciesView(groupedByCurrency: groupedByCurrencyForDay)
                        .tag(RegistryTab.currencies.rawValue)

                    // Products
                    ProductsView(
                        groupedByProduct: groupedByProduct,
                        event: event
                    )
                    .tag(RegistryTab.products.rawValue)

                    // Groups
                    GroupsView(
                        groupedByCategory: groupedByCategory,
                        groupedBySubgroup: groupedBySubgroup,
                        event: event
                    )
                    .tag(RegistryTab.groups.rawValue)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: selectedTab)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .alert("Delete Transaction?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let transaction = transactionToDelete {
                    deleteTransaction(transaction)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private func moveToPreviousDay() {
        guard hasEarlierTransactions else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
    }
    
    private func moveToNextDay() {
        guard !isToday else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        modelContext.delete(transaction)
        transactionToDelete = nil
    }
    
    private func convertToMainCurrency(_ amount: Decimal, from currencyCode: String) -> Decimal {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        let mainCode = mainCurrency?.code ?? event.currencyCode
        
        if currencyCode == mainCode { return amount }
        
        let rate = event.currencies.first(where: { $0.code == currencyCode })?.rate ?? 1.0
        return amount / rate
    }
}

// MARK: - Day Summary Box
struct DaySummaryBox: View {
    let date: Date
    let isToday: Bool
    let transactionCount: Int
    let totalAmount: Decimal
    let currencySymbol: String
    let hasEarlierTransactions: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 12) {
            // Row 1: Left Arrow | Title | Right Arrow
            GridRow {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.white)
                        .font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .disabled(!hasEarlierTransactions)
                .opacity(hasEarlierTransactions ? 1.0 : 0.3)
                
                Text(isToday ? "Today's Sales" : date.formatted(.dateTime.day().month().year()))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white)
                        .font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .disabled(isToday)
                .opacity(isToday ? 0.3 : 1.0)
            }
            
            // Row 2: Transactions and Total Amount (spanning all columns)
            GridRow {
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("Transactions")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                        Text("\(transactionCount)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 4) {
                        Text("Total Amount")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                        Text(currencySymbol + totalAmount.formatted(.number.precision(.fractionLength(2))))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
                .gridCellColumns(3)
            }
        }
        .padding()
        .background(isToday ? Color.green : Color.orange)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Transaction Card
struct TransactionCard: View {
    let transaction: Transaction
    let event: Event
    let onDelete: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var isEditingNote = false
    @State private var editedNoteText = ""
    @State private var showNoteCopied = false
    @State private var showingReceiptSheet = false
    @State private var receiptSendResult: String? = nil  // "sent" | "failed" | nil
    @State private var isSendingReceipt = false
    @State private var showingRefundMethodSheet = false
    @State private var showingRefundConfirmation = false
    @State private var isProcessingRefund = false
    @State private var refundError: String? = nil
    
    // Get payment method details from event's payment methods
    private var paymentMethodOption: PaymentMethodOption? {
        guard let data = event.paymentMethodsData,
              let methods = try? JSONDecoder().decode([PaymentMethodOption].self, from: data) else {
            return nil
        }
        
        // PRIORITY 1: Match by stored icon (handles Bizum, custom methods)
        if let storedIcon = transaction.paymentMethodIcon {
            if let match = methods.first(where: { $0.icon == storedIcon }) {
                return match
            }
        }
        
        // PRIORITY 2: Fall back to enum-based matching
        return methods.first { option in
            switch transaction.paymentMethod {
            case .cash: return option.icon == "banknote"
            case .card: return option.icon.contains("creditcard")
            case .transfer: return option.icon == "building.columns" || option.icon == "banknote.fill"
            case .other: return option.icon == "qrcode"
            }
        }
    }
    
    private var paymentIcon: String {
        // Prioritize stored icon (handles Bizum, custom methods, etc.)
        if let storedIcon = transaction.paymentMethodIcon {
            return storedIcon
        }
        
        if let option = paymentMethodOption {
            return option.icon
        }
        
        // Fallback icons
        switch transaction.paymentMethod {
        case .cash: return "banknote"
        case .card: return "creditcard"
        case .transfer: return "building.columns"
        case .other: return "qrcode"
        }
    }
    
    private var paymentIconColor: Color {
        if let option = paymentMethodOption {
            return Color(hex: option.colorHex)
        }
        return .secondary
    }

    /// Look up color for the split second method icon
    private func splitMethodIconColor(icon: String) -> Color {
        guard let data = event.paymentMethodsData,
              let methods = try? JSONDecoder().decode([PaymentMethodOption].self, from: data),
              let match = methods.first(where: { $0.icon == icon }) else {
            return .secondary
        }
        return Color(hex: match.colorHex)
    }
    
    private var totalSavings: Decimal {
        // Calculate what customer would pay at natural prices
        let naturalTotal = transaction.lineItems.reduce(Decimal(0)) { sum, item in
            // ALWAYS look up by name to avoid invalidated SwiftData references
            // Include deleted products (transaction data is sacred)
            guard let product = event.products.first(where: { 
                $0.name == item.productName
            }) else { return sum }
            
            let naturalPrice = product.price // Already in transaction currency
            return sum + (naturalPrice * Decimal(item.quantity))
        }
        
        // Actual total paid (with promos applied)
        let promoTotal = transaction.totalAmount
        
        // Savings = what they would pay - what they actually paid
        return max(0, naturalTotal - promoTotal)
    }
    
    private func currencySymbol(for code: String) -> String {
        return event.currencies.first(where: { $0.code == code })?.symbol ?? code
    }

    /// Format a unit count: whole numbers show as "N unit(s)", fractions show as "0.97 units"
    private func formatUnits(_ units: Decimal) -> String {
        let count = NSDecimalNumber(decimal: units).intValue
        let isWhole = Decimal(count) == units
        if isWhole {
            return count == 1 ? "1 unit" : "\(count) units"
        } else {
            return "\(units.formatted(.number.precision(.fractionLength(2)))) units"
        }
    }


    /// Convert a main-currency splitAmount to the charge currency for display.
    private func splitDisplayAmount(_ mainAmount: Decimal, chargeCode: String) -> Decimal {
        let mainCode = event.currencies.first(where: { $0.isMain })?.code ?? event.currencyCode
        guard chargeCode != mainCode else { return mainAmount }
        let rate = event.currencies.first(where: { $0.code == chargeCode })?.rate ?? 1
        return mainAmount * rate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Divider().padding(.horizontal, 14)
            paymentMethodSection
            Divider().padding(.horizontal, 14)
            lineItemsSection
            noteSection
            receiptEmailSection
            Divider().padding(.horizontal, 14)
            cardFooter
        }
        .background(transaction.isRefund ? Color.red.opacity(0.07) : Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(transaction.isRefund ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1))
        .sheet(isPresented: $showingReceiptSheet, content: receiptSheetContent)
        .sheet(isPresented: $showingRefundMethodSheet) {
            RefundMethodSheet(transaction: transaction) { method in Task { await issueRefund(method: method) } }
                .presentationDetents([.height(320)])
        }
        .confirmationDialog("Refund this transaction?", isPresented: $showingRefundConfirmation, titleVisibility: .visible) {
            Button("Refund in Cash", role: .destructive) { Task { await issueRefund(method: .cash) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The customer will receive \(currencySymbol(for: transaction.currencyCode))\(transaction.totalAmount.formatted(.number.precision(.fractionLength(2)))) back in cash.")
        }
        .overlay(toastOverlay)
    }

    // MARK: - Card Sections

    @ViewBuilder private var cardHeader: some View {
        HStack(alignment: .center) {
            Text(transaction.timestamp.formatted(.dateTime.hour().minute()))
                .font(.headline)
                .foregroundStyle(transaction.isRefund ? Color.red : Color.primary)
            if transaction.isRefund || transaction.isRefunded { refundStatusBadge }
            Spacer()
            if let txnRef = transaction.transactionRef {
                Text(txnRef).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("\(transaction.lineItems.count) item\(transaction.lineItems.count == 1 ? "" : "s")").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(currencySymbol(for: transaction.currencyCode) + transaction.totalAmount.formatted(.number.precision(.fractionLength(2))))
                .font(.headline.weight(.semibold))
                .foregroundStyle(transaction.isRefund ? Color.red : Color.primary)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
    }

    @ViewBuilder private var paymentMethodSection: some View {
        if transaction.isNWaySplit {
            let entries = transaction.splitEntries
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                        HStack(spacing: 5) {
                            Image(systemName: entry.methodIcon).font(.subheadline).foregroundStyle(splitMethodIconColor(icon: entry.methodIcon))
                            Text(currencySymbol(for: entry.currencyCode) + splitDisplayAmount(entry.amountInMain, chargeCode: entry.currencyCode).formatted(.number.precision(.fractionLength(2)))).font(.subheadline.weight(.medium))
                        }
                        if idx < entries.count - 1 { Text("+").font(.caption).foregroundStyle(.quaternary) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: paymentIcon).font(.subheadline).foregroundStyle(paymentIconColor)
                Text(paymentMethodOption?.name ?? transaction.paymentMethod.rawValue.capitalized).font(.subheadline).foregroundStyle(.secondary)
                if event.areCategoriesEnabled, let firstCategory = transaction.lineItems.first?.product?.category {
                    let categoryColor = Color(hex: firstCategory.hexColor).normalizeForRegistry()
                    Text(firstCategory.name).font(.caption.weight(.semibold)).foregroundStyle(categoryColor)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(categoryColor.opacity(0.15)).cornerRadius(4)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
    }

    @ViewBuilder private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(transaction.lineItems) { item in
                lineItemRow(item)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder private func lineItemRow(_ item: LineItem) -> some View {
        let isDeleted = !event.products.contains(where: { $0.name == item.productName && !$0.isDeleted })
        let product = event.products.first(where: { $0.name == item.productName && !$0.isDeleted })
        let categoryColor = product?.category.flatMap { Color(hex: $0.hexColor) } ?? .gray
        HStack {
            Circle().fill(categoryColor).frame(width: 8, height: 8)
            Text(item.productName).font(.subheadline).foregroundStyle(isDeleted ? Color.red : Color.primary).lineLimit(1)
            Spacer()
            Text("×\(item.quantity)").font(.subheadline).foregroundStyle(.secondary).padding(.trailing, 8)
            let unitPrice = item.quantity > 0 ? item.subtotal / Decimal(item.quantity) : item.subtotal
            Text(currencySymbol(for: transaction.currencyCode) + unitPrice.formatted(.number.precision(.fractionLength(2))))
                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8).frame(minWidth: 60, alignment: .trailing)
        }
    }

    @ViewBuilder private var noteSection: some View {
        let hasNote = !(transaction.note ?? "").isEmpty
        if isEditingNote || hasNote {
            Divider().padding(.horizontal, 14)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "pencil").foregroundStyle(isEditingNote ? Color.orange : Color.secondary).font(.footnote).padding(.top, 2)
                if isEditingNote {
                    TextField("Add a note…", text: $editedNoteText, axis: .vertical)
                        .font(.subheadline).textFieldStyle(.plain).lineLimit(1...5).submitLabel(.done).onSubmit { saveNote() }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Save") { saveNote() }.bold().foregroundStyle(Color.orange)
                            }
                        }
                    Button(action: saveNote) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.orange) }.buttonStyle(.borderless)
                } else {
                    Text(transaction.note ?? "").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { copyToClipboard(transaction.note ?? "") }
                        .onLongPressGesture { startEditingNote() }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    @ViewBuilder private var receiptEmailSection: some View {
        if let email = transaction.receiptEmail, !email.isEmpty {
            Divider().padding(.horizontal, 14)
            HStack(spacing: 8) {
                Image(systemName: "receipt").foregroundStyle(.blue).font(.footnote)
                Text(email).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).onTapGesture { copyToClipboard(email) }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    @ViewBuilder private var cardFooter: some View {
        HStack(alignment: .center, spacing: 16) {
            if totalSavings > 0 {
                Text("Saved " + currencySymbol(for: transaction.currencyCode) + totalSavings.formatted(.number.precision(.fractionLength(2)))).font(.subheadline).foregroundStyle(.green)
            }
            Spacer()
            Button(action: startEditingNote) { Image(systemName: "pencil").foregroundStyle(Color.orange) }
                .buttonStyle(.borderless).disabled(event.isLocked)
            Button(action: { showingReceiptSheet = true }) { Image(systemName: "envelope").foregroundStyle(Color.blue) }
                .buttonStyle(.borderless).disabled(isSendingReceipt).opacity(isSendingReceipt ? 0.4 : 1.0)
            Button(action: tapRefund) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle((transaction.isRefunded || transaction.isRefund) ? Color.secondary : Color.orange)
            }
            .buttonStyle(.borderless)
            .disabled(transaction.isRefunded || transaction.isRefund || event.isLocked || isProcessingRefund)
            .opacity((transaction.isRefunded || transaction.isRefund || event.isLocked) ? 0.4 : 1.0)
            Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(.red) }
                .buttonStyle(.borderless).disabled(event.isLocked)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func tapRefund() {
        let isStripeMethod = transaction.paymentMethod == .card
            || transaction.stripePaymentIntentId != nil
            || transaction.stripeSessionId != nil
        if isStripeMethod { showingRefundMethodSheet = true } else { showingRefundConfirmation = true }
    }
    
    // MARK: - Extracted helpers (break up body for type-checker)

    @ViewBuilder private var refundStatusBadge: some View {
        let (text, bg): (String, Color) = transaction.isRefund ? ("REFUND", .red) : ("REFUNDED", .orange)
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .cornerRadius(4)
    }

    @ViewBuilder private var toastOverlay: some View {
        if showNoteCopied {
            toastCapsule(icon: "doc.on.doc.fill", iconColor: .green, label: "Copied")
        }
        if let result = receiptSendResult {
            let isOk = result == "sent" || result == "refunded"
            toastCapsule(
                icon: isOk ? "checkmark.circle.fill" : "xmark.circle.fill",
                iconColor: isOk ? .green : .red,
                label: toastLabel(for: result)
            )
        }
    }

    private func toastLabel(for result: String) -> String {
        switch result {
        case "sent":     return "Receipt sent"
        case "refunded": return "Refund issued"
        default:         return refundError ?? "Failed"
        }
    }

    @ViewBuilder private func toastCapsule(icon: String, iconColor: Color, label: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(iconColor)
                Text(label).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(UIColor.systemBackground)).shadow(color: .black.opacity(0.2), radius: 8, y: 3))
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder private func receiptSheetContent() -> some View {
        SimpleEmailSheet(
            onComplete: { email in sendReceipt(to: email) },
            onCancel: { showingReceiptSheet = false },
            initialEmail: transaction.receiptEmail ?? ""
        )
        .presentationDetents([.height(320)])
    }

    private func sendReceipt(to email: String) {
        showingReceiptSheet = false
        isSendingReceipt = true
        Task {
            let result = await ReceiptService.sendCustomReceipt(
                transaction: transaction, event: event, email: email)
            await MainActor.run {
                isSendingReceipt = false
                if result.success {
                    transaction.receiptEmail = email
                    try? modelContext.save()
                    receiptSendResult = "sent"
                } else {
                    receiptSendResult = "failed"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { receiptSendResult = nil }
            }
        }
    }

    @MainActor
    private func issueRefund(method: RefundService.RefundMethod) async {
        isProcessingRefund = true
        do {
            try await RefundService.processRefund(
                originalTransaction: transaction,
                event: event,
                refundMethod: method,
                modelContext: modelContext
            )
            withAnimation { receiptSendResult = "refunded" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { receiptSendResult = nil }
        } catch {
            refundError = error.localizedDescription
            withAnimation { receiptSendResult = "failed" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                receiptSendResult = nil
                refundError = nil
            }
        }
        isProcessingRefund = false
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        
        // Show confirmation toast
        withAnimation {
            showNoteCopied = true
        }
        
        // Hide after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showNoteCopied = false
            }
        }
    }
    
    private func startEditingNote() {
        editedNoteText = transaction.note ?? ""
        isEditingNote = true
    }
    
    private func saveNote() {
        transaction.note = editedNoteText.isEmpty ? nil : editedNoteText
        try? modelContext.save()
        isEditingNote = false
    }
}

// MARK: - Groups View
struct GroupsView: View {
    let groupedByCategory: [RegistryView.CategoryGroup]
    let groupedBySubgroup: [RegistryView.SubgroupGroup]
    let event: Event
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // By Type Section
                if !groupedByCategory.isEmpty {
                    Text("By Type")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    ForEach(groupedByCategory) { group in
                        CategoryGroupCard(group: group, event: event)
                            .padding(.horizontal)
                    }
                }
                
                // By Subgroup Section
                if !groupedBySubgroup.isEmpty {
                    Text("By Subgroup")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    ForEach(groupedBySubgroup) { group in
                        SubgroupGroupCard(group: group, event: event)
                            .padding(.horizontal)
                    }
                }
                
                // Empty state
                if groupedByCategory.isEmpty && groupedBySubgroup.isEmpty {
                    ContentUnavailableView(
                        "No Groups",
                        systemImage: "square.3.layers.3d",
                        description: Text("No data available for grouping")
                    )
                    .padding(.top, 60)
                }
            }
            .padding(.bottom)
        }
    }
}

// MARK: - Category Group Card
struct CategoryGroupCard: View {
    let group: RegistryView.CategoryGroup
    let event: Event
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Category name + Total
            HStack(spacing: 12) {
                Text(group.category.name)
                    .font(.headline)
                    .foregroundStyle(Color(hex: group.category.hexColor).normalizeForRegistry())
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("\(group.totalUnits) units")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                
                Text(mainCurrencySymbol + group.total.formatted(.number.precision(.fractionLength(2))))
                    .font(.headline)
                    .foregroundStyle(Color(hex: group.category.hexColor).normalizeForRegistry())
                    .frame(width: 90, alignment: .trailing)
            }
            
            // Currency sections
            ForEach(group.currencySections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.currencyCode)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: group.category.hexColor).normalizeForRegistry())
                    
                    ForEach(section.paymentMethods) { pm in
                        HStack(spacing: 12) {
                            Text(pm.methodName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(formatUnits(pm.units))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                            
                            Text(section.currencySymbol + pm.subtotal.formatted(.number.precision(.fractionLength(2))))
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.leading, 16)
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    
    private func currencySymbol(for code: String) -> String {
        return event.currencies.first(where: { $0.code == code })?.symbol ?? code
    }

    /// Format a unit count: whole numbers show as "N unit(s)", fractions show as "0.97 units"
    private func formatUnits(_ units: Decimal) -> String {
        let count = NSDecimalNumber(decimal: units).intValue
        let isWhole = Decimal(count) == units
        if isWhole {
            return count == 1 ? "1 unit" : "\(count) units"
        } else {
            return "\(units.formatted(.number.precision(.fractionLength(2)))) units"
        }
    }

    
    private var mainCurrencySymbol: String {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        return mainCurrency?.symbol ?? "$"
    }
}

// MARK: - Subgroup Group Card
struct SubgroupGroupCard: View {
    let group: RegistryView.SubgroupGroup
    let event: Event
    
    private var color: Color {
        if let category = group.category {
            return Color(hex: category.hexColor).normalizeForRegistry()
        }
        return .gray.opacity(0.8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Subgroup name + Total
            HStack(spacing: 12) {
                Text(group.subgroupName)
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("\(group.totalUnits) units")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                
                Text(mainCurrencySymbol + group.total.formatted(.number.precision(.fractionLength(2))))
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(width: 90, alignment: .trailing)
            }
            
            // Product rows
            ForEach(group.products) { product in
                HStack {
                    Text(product.productName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(mainCurrencySymbol + product.subtotal.formatted(.number.precision(.fractionLength(2))))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 70, alignment: .trailing)
                        .padding(.trailing, 8)
                }
                .padding(.leading, 12)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    
    private var mainCurrencySymbol: String {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        return mainCurrency?.symbol ?? "$"
    }
}

// MARK: - Products View
struct ProductsView: View {
    let groupedByProduct: [RegistryView.ProductGroup]
    let event: Event
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if groupedByProduct.isEmpty {
                    ContentUnavailableView(
                        "No Products",
                        systemImage: "cube.box",
                        description: Text("No products sold this day")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(groupedByProduct) { group in
                        ProductGroupCard(group: group, event: event)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Product Group Card
struct ProductGroupCard: View {
    let group: RegistryView.ProductGroup
    let event: Event
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Category color square + Product name + Total + Units
            HStack(alignment: .top, spacing: 8) {
                // Category color square
                if let category = group.category {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: category.hexColor).normalizeForRegistry())
                        .frame(width: 24, height: 24)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    // Check if product is deleted
                    let isDeleted = !event.products.contains(where: { $0.name == group.productName && !$0.isDeleted })
                    
                    Text(group.productName)
                        .font(.headline)
                        .foregroundStyle(isDeleted ? .red : .primary)
                    
                    Text("\(group.totalUnits) units")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(mainCurrencySymbol + group.total.formatted(.number.precision(.fractionLength(2))))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(group.category.map { Color(hex: $0.hexColor).normalizeForRegistry() } ?? .primary)
            }
            
            Divider()
            
            // Currency sections
            ForEach(group.currencySections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.currencyCode)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(section.paymentMethods) { pm in
                        HStack(spacing: 12) {
                            // Column 1: Method name (flexible width, left-aligned)
                            Text(pm.methodName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Column 2: Units (fixed width, right-aligned)
                            Text(formatUnits(pm.units))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                            
                            // Column 3: Subtotal (fixed width, right-aligned)
                            Text(section.currencySymbol + pm.subtotal.formatted(.number.precision(.fractionLength(2))))
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.leading, 16)
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    
    private func currencySymbol(for code: String) -> String {
        return event.currencies.first(where: { $0.code == code })?.symbol ?? code
    }

    /// Format a unit count: whole numbers show as "N unit(s)", fractions show as "0.97 units"
    private func formatUnits(_ units: Decimal) -> String {
        let count = NSDecimalNumber(decimal: units).intValue
        let isWhole = Decimal(count) == units
        if isWhole {
            return count == 1 ? "1 unit" : "\(count) units"
        } else {
            return "\(units.formatted(.number.precision(.fractionLength(2)))) units"
        }
    }

    
    private var mainCurrencySymbol: String {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        return mainCurrency?.symbol ?? "$"
    }
}

// MARK: - Previews
#Preview("DaySummaryBox - Today") {
    DaySummaryBox(
        date: Date(),
        isToday: true,
        transactionCount: 16,
        totalAmount: 1754.00,
        currencySymbol: "£",
        hasEarlierTransactions: false,
        onPrevious: {},
        onNext: {}
    )
    .padding()
}

#Preview("DaySummaryBox - Past Date") {
    DaySummaryBox(
        date: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
        isToday: false,
        transactionCount: 5,
        totalAmount: 847.99,
        currencySymbol: "$",
        hasEarlierTransactions: true,
        onPrevious: {},
        onNext: {}
    )
    .padding()
}

#Preview("DaySummaryBox - Long Amount") {
    DaySummaryBox(
        date: Date(),
        isToday: true,
        transactionCount: 142,
        totalAmount: 123456.78,
        currencySymbol: "€",
        hasEarlierTransactions: true,
        onPrevious: {},
        onNext: {}
    )
    .padding()
}
