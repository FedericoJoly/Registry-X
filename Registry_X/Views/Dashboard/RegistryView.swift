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
    
    enum RegistryTab {
        case transactions
        case products
        case groups
    }
    
    // Normalize date to start of day
    private var selectedDayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }
    
    private var selectedDayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: selectedDayStart) ?? selectedDayStart
    }
    
    // Transactions for selected day
    private var dayTransactions: [Transaction] {
        event.transactions.filter { transaction in
            transaction.timestamp >= selectedDayStart && transaction.timestamp < selectedDayEnd
        }.sorted { $0.timestamp > $1.timestamp }
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
        let units: Int
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
                let product = event.products.first(where: { 
                    $0.name == item.productName && !$0.isDeleted 
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
            var currencyDict: [String: [(method: String, quantity: Int, subtotal: Decimal)]] = [:]
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0
            
            for (item, currencyCode) in items {
                // Convert to main currency for total
                let subtotalInMain = convertToMainCurrency(item.subtotal, from: currencyCode)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
                
                // Find transaction for this item to get payment method
                if let transaction = dayTransactions.first(where: { $0.lineItems.contains(where: { $0.id == item.id }) }) {
                    let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
                    
                    if currencyDict[currencyCode] == nil {
                        currencyDict[currencyCode] = []
                    }
                    
                    currencyDict[currencyCode]!.append((method: methodName, quantity: item.quantity, subtotal: item.subtotal))
                }
            }
            
            // Convert to CurrencySections with aggregated payment methods
            var currencySections: [CurrencySection] = []
            for (code, transactions) in currencyDict {
                // Aggregate by method
                var methodDict: [String: (units: Int, subtotal: Decimal)] = [:]
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
                        let product = event.products.first(where: { 
                            $0.name == item.productName && !$0.isDeleted 
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
                
                if let existing = productDict[item.productName] {
                    productDict[item.productName] = (existing.quantity + item.quantity, existing.subtotal + item.subtotal)
                } else {
                    productDict[item.productName] = (item.quantity, item.subtotal)
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
                    let product = event.products.first(where: { 
                        $0.name == item.productName && !$0.isDeleted 
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
            var currencyDict: [String: [(method: String, quantity: Int, subtotal: Decimal)]] = [:]
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0
            
            for (item, currencyCode) in items {
                // Convert to main currency for total
                let subtotalInMain = convertToMainCurrency(item.subtotal, from: currencyCode)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
                
                // Find transaction for this item to get payment method
                if let transaction = dayTransactions.first(where: { $0.lineItems.contains(where: { $0.id == item.id }) }) {
                    let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
                    
                    if currencyDict[currencyCode] == nil {
                        currencyDict[currencyCode] = []
                    }
                    
                    currencyDict[currencyCode]!.append((method: methodName, quantity: item.quantity, subtotal: item.subtotal))
                }
            }
            
            // Convert to CurrencySections with aggregated payment methods
            var currencySections: [CurrencySection] = []
            for (code, transactions) in currencyDict {
                // Aggregate by method
                var methodDict: [String: (units: Int, subtotal: Decimal)] = [:]
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
                
                // Tabs: Transactions | Products | Groups
                HStack(spacing: 0) {
                    Button(action: { selectedTab = .transactions }) {
                        Text("Transactions")
                            .font(.headline)
                            .foregroundStyle(selectedTab == .transactions ? .green : .secondary)
                            .padding(.bottom, 6)
                            .overlay(alignment: .bottom) {
                                if selectedTab == .transactions {
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button(action: { selectedTab = .products }) {
                        Text("Products")
                            .font(.headline)
                            .foregroundStyle(selectedTab == .products ? .green : .secondary)
                            .padding(.bottom, 6)
                            .overlay(alignment: .bottom) {
                                if selectedTab == .products {
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button(action: { selectedTab = .groups }) {
                        Text("Groups")
                            .font(.headline)
                            .foregroundStyle(selectedTab == .groups ? .green : .secondary)
                            .padding(.bottom, 6)
                            .overlay(alignment: .bottom) {
                                if selectedTab == .groups {
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                
                // Content based on selected tab
                if selectedTab == .transactions {
                    // Transaction List
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
                    }
                } else if selectedTab == .products {
                    // Products View
                    ProductsView(
                        groupedByProduct: groupedByProduct,
                        event: event
                    )
                } else {
                    // Groups View
                    GroupsView(
                        groupedByCategory: groupedByCategory,
                        groupedBySubgroup: groupedBySubgroup,
                        event: event
                    )
                }
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
        let converted = amount / rate
        
        // Apply round-up if enabled
        if event.isTotalRoundUp {
            return Decimal(ceil(NSDecimalNumber(decimal: converted).doubleValue))
        }
        return converted
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
    
    private var totalSavings: Decimal {
        // Calculate what customer would pay at natural prices
        let naturalTotal = transaction.lineItems.reduce(Decimal(0)) { sum, item in
            // ALWAYS look up by name to avoid invalidated SwiftData references
            guard let product = event.products.first(where: { 
                $0.name == item.productName && !$0.isDeleted 
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // HEADER ROW: Time + Icon | Amount | Delete
            HStack {
                HStack(spacing: 8) {
                    Text(transaction.timestamp.formatted(.dateTime.hour().minute()))
                        .font(.headline)
                    
                    Image(systemName: paymentIcon)
                        .foregroundStyle(paymentIconColor)
                }
                
                Spacer()
                
                Text(currencySymbol(for: transaction.currencyCode) + transaction.totalAmount.formatted(.number.precision(.fractionLength(2))))
                    .font(.headline)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .font(.title3)
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .disabled(event.isLocked)
            }
            
            // META ROW: Transaction ID + Category | Savings
            HStack {
                HStack(spacing: 4) {
                    if let txnRef = transaction.transactionRef {
                        Text(txnRef)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(transaction.lineItems.count) item\(transaction.lineItems.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Category badge (10% darker, only if categories enabled)
                    if event.areCategoriesEnabled,
                       let firstCategory = transaction.lineItems.first?.product?.category {
                        let categoryColor = Color(hex: firstCategory.hexColor).normalizeForRegistry()
                        Text(firstCategory.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(categoryColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                if totalSavings > 0 {
                    Text("Saved " + currencySymbol(for: transaction.currencyCode) + totalSavings.formatted(.number.precision(.fractionLength(2))))
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
            
            Divider()
            
            // LINE ITEMS
            VStack(alignment: .leading, spacing: 6) {
                ForEach(transaction.lineItems) { item in
                    HStack {
                        // Check if product is deleted
                        let isDeleted = !event.products.contains(where: { $0.name == item.productName && !$0.isDeleted })
                        // ALWAYS look up by name to avoid invalidated SwiftData references  
                        let product = event.products.first(where: { $0.name == item.productName && !$0.isDeleted })
                        let categoryColor = product?.category.flatMap { Color(hex: $0.hexColor) } ?? .gray
                        
                        Circle()
                            .fill(categoryColor)
                            .frame(width: 10, height: 10)
                        
                        Text(item.productName)
                            .font(.subheadline)
                            .foregroundStyle(isDeleted ? .red : .primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("×\(item.quantity)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 10)
                        
                        let unitPrice = item.quantity > 0 ? item.subtotal / Decimal(item.quantity) : item.subtotal
                        Text(currencySymbol(for: transaction.currencyCode) + unitPrice.formatted(.number.precision(.fractionLength(2))))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
            }
            
            // NOTES AND EMAIL SECTION
            if (transaction.note != nil && !transaction.note!.isEmpty) || (transaction.receiptEmail != nil && !transaction.receiptEmail!.isEmpty) {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    // Display note with pencil icon
                    if let note = transaction.note, !note.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            
                            if isEditingNote {
                                // Editing mode with TextField
                                TextField("Note", text: $editedNoteText, axis: .vertical)
                                    .font(.subheadline)
                                    .textFieldStyle(.plain)
                                    .lineLimit(1...5)
                                
                                // Tick button to save
                                Button(action: saveNote) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.title3)
                                }
                                .buttonStyle(.borderless)
                            } else {
                                // Display mode
                                Text(note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .onTapGesture {
                                        copyToClipboard(note)
                                    }
                                    .onLongPressGesture {
                                        startEditingNote()
                                    }
                            }
                        }
                    }
                    
                    // Display receipt email with receipt icon
                    if let email = transaction.receiptEmail, !email.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "receipt")
                                .foregroundStyle(.blue)
                                .font(.subheadline)
                            
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onTapGesture {
                                    copyToClipboard(email)
                                }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .overlay(
            Group {
                if showNoteCopied {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc.fill")
                                .foregroundStyle(.green)
                            Text("Note copied")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(UIColor.systemBackground))
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                        )
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        )
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
                            
                            Text("\(pm.units) units")
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
                            Text("\(pm.units) units")
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
        onPrevious: { print("Previous") },
        onNext: { print("Next") }
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
        onPrevious: { print("Previous") },
        onNext: { print("Next") }
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
        onPrevious: { print("Previous") },
        onNext: { print("Next") }
    )
    .padding()
}
