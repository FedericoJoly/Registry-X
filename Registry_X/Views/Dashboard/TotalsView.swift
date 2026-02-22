import SwiftUI
import SwiftData

struct TotalsView: View {
    @Bindable var event: Event
    var onQuit: (() -> Void)? = nil
    
    @Environment(AuthService.self) private var authService
    @State private var selectedTab: TotalsTab = .currencies
    
    enum TotalsTab: Int, CaseIterable {
        case currencies
        case products
        case groups

        var title: String {
            switch self {
            case .currencies: return "Currencies"
            case .products:   return "Products"
            case .groups:     return "Groups"
            }
        }
    }
    
    // MARK: - Data Structures
    
    struct CategoryTotal: Identifiable {
        let id = UUID()
        let category: Category
        let total: Decimal
    }
    
    struct CurrencyGroup: Identifiable {
        let id = UUID()
        let currencyCode: String
        let currencySymbol: String
        let total: Decimal
        let paymentMethods: [PaymentMethodRow]
    }
    
    struct PaymentMethodRow: Identifiable {
        let id = UUID()
        let methodName: String
        let units: Decimal   // may be fractional for split transactions
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
    
    struct CurrencySection: Identifiable {
        let id = UUID()
        let currencyCode: String
        let currencySymbol: String
        let paymentMethods: [PaymentMethodRow]
    }
    
    struct CategoryGroup: Identifiable {
        let id = UUID()
        let category: Category
        let totalUnits: Int
        let total: Decimal
        let currencySections: [CurrencySection]
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
        let units: Decimal   // may be fractional for split transactions
        let subtotal: Decimal
    }
    
    // MARK: - Computed Properties
    
    private var allTransactions: [Transaction] {
        event.transactions
    }
    
    private var mainCurrency: Currency? {
        event.currencies.first(where: { $0.isMain })
    }
    
    private var mainCurrencySymbol: String {
        mainCurrency?.symbol ?? "$"
    }
    
    private var mainCurrencyCode: String {
        mainCurrency?.code ?? "USD"
    }
    
    private var totalAmount: Decimal {
        var total = Decimal(0)
        for transaction in allTransactions {
            let amountInMain = convertToMainCurrency(transaction.totalAmount, from: transaction.currencyCode)
            total += amountInMain
        }
        return total
    }
    
    private var categoryTotals: [CategoryTotal] {
        var categoryDict: [UUID: (category: Category, total: Decimal)] = [:]
        
        for transaction in allTransactions {
            for item in transaction.lineItems {
                // ALWAYS look up by name to avoid invalidated SwiftData references
                // Include deleted products (transaction data is sacred)
                let product = event.products.first(where: { 
                    $0.name == item.productName
                })
                let category = product?.category
                
                if let category = category {
                    let subtotalInMain = convertToMainCurrency(item.subtotal, from: transaction.currencyCode)
                    
                    if let existing = categoryDict[category.id] {
                        categoryDict[category.id] = (category, existing.total + subtotalInMain)
                    } else {
                        categoryDict[category.id] = (category, subtotalInMain)
                    }
                }
            }
        }
        
        return categoryDict.map { CategoryTotal(category: $0.value.category, total: $0.value.total) }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }
    
    private var groupedByCurrency: [CurrencyGroup] {
        var currencyDict: [String: [(method: String, quantity: Decimal, subtotal: Decimal)]] = [:]
        
        for transaction in allTransactions {
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
                let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
                if currencyDict[transaction.currencyCode] == nil { currencyDict[transaction.currencyCode] = [] }
                currencyDict[transaction.currencyCode]!.append((method: methodName, quantity: totalQty, subtotal: transaction.totalAmount))
            }
        }
        
        var result: [CurrencyGroup] = []
        for (code, transactions) in currencyDict {
            var methodDict: [String: (units: Decimal, subtotal: Decimal)] = [:]
            var total = Decimal(0)
            
            for trans in transactions {
                total += trans.subtotal
                
                if let existing = methodDict[trans.method] {
                    methodDict[trans.method] = (existing.units + trans.quantity, existing.subtotal + trans.subtotal)
                } else {
                    methodDict[trans.method] = (trans.quantity, trans.subtotal)
                }
            }
            
            let paymentMethods = methodDict.map { (method, value) in
                PaymentMethodRow(methodName: method, units: value.units, subtotal: value.subtotal)
            }.sorted { $0.methodName < $1.methodName }
            
            result.append(CurrencyGroup(
                currencyCode: code,
                currencySymbol: currencySymbol(for: code),
                total: total,
                paymentMethods: paymentMethods
            ))
        }
        
        return result.sorted { $0.currencyCode < $1.currencyCode }
    }
    
    private var groupedByProduct: [ProductGroup] {
        var productDict: [String: (category: Category?, items: [(item: LineItem, currencyCode: String)])] = [:]
        
        for transaction in allTransactions {
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
        
        var result: [ProductGroup] = []
        for (productName, value) in productDict {
            let (category, items) = value
            
            var currencyDict: [String: [(method: String, quantity: Decimal, subtotal: Decimal)]] = [:]
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0
            
            for (item, currencyCode) in items {
                let subtotalInMain = convertToMainCurrency(item.subtotal, from: currencyCode)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
                
                if let transaction = allTransactions.first(where: { $0.lineItems.contains(where: { $0.id == item.id }) }) {
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
                                let rounded = NSDecimalNumber(decimal: item.subtotal * ratio).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).decimalValue
                                share = rounded
                                remaining -= rounded
                            }
                            if share > 0 {
                                let qtyShare = NSDecimalNumber(decimal: Decimal(item.quantity) * ratio).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).decimalValue
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
            
            var currencySections: [CurrencySection] = []
            for (code, transactions) in currencyDict {
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
    
    private var groupedByCategory: [CategoryGroup] {
        var categoryDict: [UUID: (category: Category, items: [(item: LineItem, currencyCode: String)])] = [:]
        
        for transaction in allTransactions {
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
        
        var result: [CategoryGroup] = []
        for (_, value) in categoryDict {
            let (category, items) = value
            
            var currencyDict: [String: [(method: String, quantity: Decimal, subtotal: Decimal)]] = [:]
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0
            
            for (item, currencyCode) in items {
                let subtotalInMain = convertToMainCurrency(item.subtotal, from: currencyCode)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
                
                if let transaction = allTransactions.first(where: { $0.lineItems.contains(where: { $0.id == item.id }) }) {
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
                                let rounded = NSDecimalNumber(decimal: item.subtotal * ratio).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).decimalValue
                                share = rounded
                                remaining -= rounded
                            }
                            if share > 0 {
                                let qtyShare = NSDecimalNumber(decimal: Decimal(item.quantity) * ratio).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).decimalValue
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
            
            var currencySections: [CurrencySection] = []
            for (code, transactions) in currencyDict {
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
        
        for transaction in allTransactions {
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
        
        var subgroupResult: [SubgroupGroup] = []
        for (subgroupName, value) in subgroupDict {
            let (category, items) = value

            var productDict: [String: (quantity: Int, subtotal: Decimal)] = [:]
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0

            for (item, currencyCode) in items {
                let subtotalInMain: Decimal = convertToMainCurrency(item.subtotal, from: currencyCode)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
                if let existing = productDict[item.productName] {
                    productDict[item.productName] = (existing.quantity + item.quantity, existing.subtotal + item.subtotal)
                } else {
                    productDict[item.productName] = (item.quantity, item.subtotal)
                }
            }

            var products: [ProductRow] = productDict.map { (name, val) in
                ProductRow(productName: name, units: Decimal(val.quantity), subtotal: val.subtotal)
            }
            products.sort { prod1, prod2 in
                guard let p1 = event.products.first(where: { $0.name == prod1.productName }),
                      let p2 = event.products.first(where: { $0.name == prod2.productName }) else {
                    return prod1.productName < prod2.productName
                }
                return p1.sortOrder < p2.sortOrder
            }

            subgroupResult.append(SubgroupGroup(
                subgroupName: subgroupName,
                category: category,
                totalUnits: totalUnits,
                total: totalInMainCurrency,
                products: products
            ))
        }
        return subgroupResult.sorted { $0.subgroupName < $1.subgroupName }
    }
    
    // MARK: - Helper Functions
    
    private func convertToMainCurrency(_ amount: Decimal, from currencyCode: String) -> Decimal {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        let mainCode = mainCurrency?.code ?? event.currencyCode
        
        if currencyCode == mainCode { return amount }
        
        let rate = event.currencies.first(where: { $0.code == currencyCode })?.rate ?? 1.0
        return amount / rate
    }
    
    private func currencySymbol(for code: String) -> String {
        return event.currencies.first(where: { $0.code == code })?.symbol ?? code
    }

    /// Format a unit count: whole numbers show as "N unit(s)", fractions show "0.97 units"
    
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
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // INFO HEADER
            if let user = authService.currentUser {
                EventInfoHeader(event: event, userFullName: user.fullName, onQuit: onQuit)
            } else {
                EventInfoHeader(event: event, userFullName: "Operator", onQuit: onQuit)
            }

            // Blue Header Box (scrollable on its own)
            ScrollView {
                TotalsHeaderBox(
                    eventName: event.name,
                    totalAmount: totalAmount,
                    mainCurrencySymbol: mainCurrencySymbol,
                    mainCurrencyCode: mainCurrencyCode,
                    categoryTotals: categoryTotals
                )
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)

            // ── Tab header (3-visible, swipeable) ────────────────────────
            HStack(spacing: 0) {
                ForEach(TotalsTab.allCases, id: \.self) { tab in
                    Button(action: { withAnimation { selectedTab = tab } }) {
                        Text(tab.title)
                            .font(.headline)
                            .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 6)
                            .overlay(alignment: .bottom) {
                                if selectedTab == tab {
                                    Rectangle().fill(Color.blue).frame(height: 2)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)


            // ── Swipeable content (outside ScrollView so TabView gets real height) ──
            TabView(selection: Binding(
                get: { selectedTab.rawValue },
                set: { selectedTab = TotalsTab(rawValue: $0) ?? .currencies }
            )) {
                CurrenciesView(groupedByCurrency: groupedByCurrency)
                    .tag(TotalsTab.currencies.rawValue)
                TotalsProductsView(groupedByProduct: groupedByProduct, event: event)
                    .tag(TotalsTab.products.rawValue)
                TotalsGroupsView(
                    groupedByCategory: groupedByCategory,
                    groupedBySubgroup: groupedBySubgroup,
                    event: event
                )
                .tag(TotalsTab.groups.rawValue)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: selectedTab)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}


// MARK: - Shared Helpers
/// Format a unit count for display: whole numbers show as "N unit(s)", fractions show "0.97 units"


// MARK: - Shared Helpers
/// Format a unit count for display: whole numbers show as "N unit(s)", fractions show "0.97 units"
private func formatUnits(_ units: Decimal) -> String {
    let count = NSDecimalNumber(decimal: units).intValue
    let isWhole = Decimal(count) == units
    if isWhole {
        return count == 1 ? "1 unit" : "\(count) units"
    } else {
        return "\(units.formatted(.number.precision(.fractionLength(2)))) units"
    }
}

// MARK: - Totals Header Box
struct TotalsHeaderBox: View {
    let eventName: String
    let totalAmount: Decimal
    let mainCurrencySymbol: String
    let mainCurrencyCode: String
    let categoryTotals: [TotalsView.CategoryTotal]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text("\(eventName) Totals")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            // Category breakdown
            VStack(alignment: .leading, spacing: 8) {
                ForEach(categoryTotals) { catTotal in
                    HStack {
                        Circle()
                            .fill(Color(hex: catTotal.category.hexColor).normalizeForRegistry())
                            .frame(width: 10, height: 10)
                        
                        Text("\(catTotal.category.name) Subtotal")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Text(mainCurrencySymbol + catTotal.total.formatted(.number.precision(.fractionLength(2))))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            
            Divider()
                .background(.white.opacity(0.3))
            
            // Total
            HStack {
                Text("Total")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(mainCurrencySymbol + totalAmount.formatted(.number.precision(.fractionLength(2))))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

// MARK: - Currencies View
struct CurrenciesView: View {
    let groupedByCurrency: [TotalsView.CurrencyGroup]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if groupedByCurrency.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "banknote",
                        description: Text("No sales recorded")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(groupedByCurrency) { group in
                        CurrencyGroupCard(group: group)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Currency Group Card
struct CurrencyGroupCard: View {
    let group: TotalsView.CurrencyGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Currency code + Total
            HStack {
                Text(group.currencyCode)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(group.currencySymbol + group.total.formatted(.number.precision(.fractionLength(2))))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            
            Divider()
            
            // Payment methods
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.paymentMethods) { pm in
                    HStack {
                        Text(pm.methodName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(group.currencySymbol + pm.subtotal.formatted(.number.precision(.fractionLength(2))))
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.leading, 12)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Totals Products View
struct TotalsProductsView: View {
    let groupedByProduct: [TotalsView.ProductGroup]
    let event: Event
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if groupedByProduct.isEmpty {
                    ContentUnavailableView(
                        "No Products",
                        systemImage: "cube.box",
                        description: Text("No products sold")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(groupedByProduct) { group in
                        TotalsProductGroupCard(group: group, event: event)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Totals Product Group Card
struct TotalsProductGroupCard: View {
    let group: TotalsView.ProductGroup
    let event: Event
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top, spacing: 8) {
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
    
    private var mainCurrencySymbol: String {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        return mainCurrency?.symbol ?? "$"
    }
}

// MARK: - Totals Groups View
struct TotalsGroupsView: View {
    let groupedByCategory: [TotalsView.CategoryGroup]
    let groupedBySubgroup: [TotalsView.SubgroupGroup]
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
                        TotalsCategoryGroupCard(group: group, event: event)
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
                        TotalsSubgroupGroupCard(group: group, event: event)
                            .padding(.horizontal)
                    }
                }
                
                if groupedByCategory.isEmpty && groupedBySubgroup.isEmpty {
                    ContentUnavailableView(
                        "No Groups",
                        systemImage: "folder",
                        description: Text("No categorized sales")
                    )
                    .padding(.top, 60)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Totals Category Group Card
struct TotalsCategoryGroupCard: View {
    let group: TotalsView.CategoryGroup
    let event: Event
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    
    private var mainCurrencySymbol: String {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        return mainCurrency?.symbol ?? "$"
    }
}

// MARK: - Totals Subgroup Group Card
struct TotalsSubgroupGroupCard: View {
    let group: TotalsView.SubgroupGroup
    let event: Event
    
    private var color: Color {
        if let category = group.category {
            return Color(hex: category.hexColor).normalizeForRegistry()
        }
        return .gray.opacity(0.8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
