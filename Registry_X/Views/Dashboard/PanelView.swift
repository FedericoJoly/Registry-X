import SwiftUI
import SwiftData

enum OverrideTarget: Equatable {
    case generalTotal
    case categorySubtotal(categoryId: UUID)
}

struct PanelView: View {
    @Bindable var event: Event
    var onQuit: (() -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    
    // POS State
    @State private var cart: [UUID: Int] = [:] // ProductID : Quantity
    @State private var currentCurrencyCode: String
    @State private var note: String = ""
    @State private var selectedTab = 0 // For category paging
    @State private var activeDiscountPromoIds: Set<UUID> = [] // Discount promos toggled ON in this session
    
    // Alerts
    @State private var showingTransactionNotification = false
    @State private var showingClearConfirmation = false
    @State private var showingPaymentMethodSheet = false
    @State private var selectedPaymentMethod: PaymentMethod = .cash
    
    // Stripe Payment State
    @State private var showingStripeCardPayment = false
    @State private var showingTapToPayEducation = false
    @StateObject private var tapToPayEducationManager = TapToPayEducationManager.shared
    @State private var showingStripeQRPayment = false
    @State private var showingBizumPayment = false
    @State private var pendingTransaction: Transaction?
    @State private var selectedMethodOption: PaymentMethodOption?
    
    // Receipt Email State (for tap-to-pay)
    @State private var showingReceiptPrompt = false
    @State private var showingReceiptEmailSheet = false
    @State private var pendingPaymentIntentId: String?
    @State private var pendingTxnRef: String?
    @State private var pendingReceiptEmail: String?
    
    // Manual Payment Receipt State (for cash/bizum/transfer)
    @State private var showingManualReceiptPrompt = false
    @State private var showingManualReceiptEmailSheet = false
    @State private var pendingManualCheckoutPaymentMethod: PaymentMethod?
    
    // Keyboard handling
    @State private var keyboardHeight: CGFloat = 0
    
    // Manual Override State
    @State private var overriddenTotal: Decimal? = nil
    @State private var overriddenCategoryTotals: [UUID: Decimal] = [:]
    @State private var showingOverrideSheet = false
    @State private var overrideTarget: OverrideTarget? = nil
    @State private var overrideInputText = ""
    
    init(event: Event, onQuit: (() -> Void)? = nil) {
        self.event = event
        self.onQuit = onQuit
        // Use main currency or fallback to first enabled currency
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        _currentCurrencyCode = State(initialValue: mainCurrency?.code ?? event.currencyCode)
    }
    
    var activeCategories: [Category] {
        event.categories.filter { cat in
            cat.isEnabled && event.products.contains(where: { $0.category == cat && $0.isActive && !$0.isDeleted })
        }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var rate: Decimal {
        // Find main currency
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        let mainCode = mainCurrency?.code ?? event.currencyCode
        
        if currentCurrencyCode == mainCode { return 1.0 }
        
        // Find selected currency and return its rate
        return event.currencies.first(where: { $0.code == currentCurrencyCode })?.rate ?? 1.0
    }
    
    var derivedTotal: Decimal {
        // If general total is overridden, return that
        if let overridden = overriddenTotal {
            return overridden
        }
        
        // Process ALL active combo promos (supports multiple combos)
        let activeComboPromos = event.promos.filter {
            $0.isActive && !$0.isDeleted && $0.mode == .combo
        }
        
        var comboTotal: Decimal = 0
        var comboProductIds: Set<UUID> = []
        
        for comboPromo in activeComboPromos {
            // Build cart for this combo's products only
            var comboCart: [UUID: Int] = [:]
            for (productId, qty) in cart {
                if qty > 0, comboPromo.comboProducts.contains(productId),
                   let product = event.products.first(where: { $0.id == productId }),
                   product.isPromo {
                    comboCart[productId] = qty
                }
            }
            
            // Check if this combo is complete (all products present)
            let allProductsPresent = comboPromo.comboProducts.allSatisfy { comboCart[$0] ?? 0 > 0 }
            
            if allProductsPresent {
                // Only exclude from category totals if combo is complete
                comboProductIds.formUnion(comboCart.keys)
                comboTotal += calculateComboPrice(promo: comboPromo, cart: comboCart)
            }
            // If combo incomplete, products will be priced naturally via category subtotals
        }
        
        // Process ALL active N x M promos
        let activeNxMPromos = event.promos.filter {
            $0.isActive && !$0.isDeleted && $0.mode == .nxm
        }
        
        var nxmTotal: Decimal = 0
        var nxmProductIds: Set<UUID> = []
        
        for nxmPromo in activeNxMPromos {
            guard let n = nxmPromo.nxmN, let m = nxmPromo.nxmM,
                  n > m && m >= 1 else {
                continue
            }
            
            // Group eligible products by their price
            var priceGroups: [Decimal: (qty: Int, productIds: Set<UUID>)] = [:]
            
            for (productId, qty) in cart {
                if qty > 0,
                   nxmPromo.nxmProducts.contains(productId),
                   let product = event.products.first(where: { $0.id == productId }),
                   product.isPromo {
                    let convertedPrice = convertPrice(product.price)
                    if priceGroups[convertedPrice] != nil {
                        priceGroups[convertedPrice]!.qty += qty
                        priceGroups[convertedPrice]!.productIds.insert(productId)
                    } else {
                        priceGroups[convertedPrice] = (qty: qty, productIds: [productId])
                    }
                }
            }
            
            // Skip if no eligible products
            guard !priceGroups.isEmpty else {
                continue
            }
            
            // Apply N x M discount to each price group separately
            var promoTotal: Decimal = 0
            var promoProductIds: Set<UUID> = []
            
            for (price, group) in priceGroups {
                let qty = group.qty
                
                // Calculate how many items to pay for in this price group
                let completeSets = qty / n
                let remainder = qty % n
                let itemsPaidFor = (completeSets * m) + remainder
                
                // Add to promo total
                promoTotal += price * Decimal(itemsPaidFor)
                promoProductIds.formUnion(group.productIds)
            }
            
            // Track products and add to total
            nxmProductIds.formUnion(promoProductIds)
            nxmTotal += promoTotal
        }
        
        // Calculate category totals (excluding products already in combo or N x M)
        var excludedProducts = comboProductIds
        excludedProducts.formUnion(nxmProductIds)
        
        var sum: Decimal = comboTotal + nxmTotal
        for category in activeCategories {
            let categorySum = categorySubtotal(for: category.id, excludeProducts: excludedProducts)
            sum += categorySum
        }
        
        // Handle products without assigned category (only if no categories are enabled)
        if activeCategories.isEmpty {
            for (id, qty) in cart {
                // Skip products already counted in combo or N x M promos
                if excludedProducts.contains(id) {
                    continue
                }
                if qty > 0, let product = event.products.first(where: { $0.id == id }) {
                    sum += convertPrice(product.price) * Decimal(qty)
                }
            }
        }
        
        // Apply active discount promos (additive, applied after all other promos)
        let activeDiscountPromos = event.promos.filter {
            $0.isActive && !$0.isDeleted && $0.mode == .discount && activeDiscountPromoIds.contains($0.id)
        }
        for discountPromo in activeDiscountPromos {
            guard let value = discountPromo.discountValue, value > 0 else { continue }
            let target = DiscountTarget(rawValue: discountPromo.discountTarget ?? "total") ?? .total
            let type_ = DiscountType(rawValue: discountPromo.discountType ?? "percentage") ?? .percentage
            
            if target == .total {
                // Apply to entire sum
                let deduction: Decimal = type_ == .percentage
                    ? sum * (value / 100)
                    : value
                sum = max(0, sum - deduction)
            } else {
                // Apply to selected products only
                let selectedIds = (try? JSONDecoder().decode(Set<UUID>.self, from: discountPromo.discountProductIds ?? Data())) ?? []
                var productDeduction: Decimal = 0
                for (productId, qty) in cart {
                    guard qty > 0, selectedIds.contains(productId),
                          let product = event.products.first(where: { $0.id == productId }) else { continue }
                    let productSubtotal = convertPrice(product.price) * Decimal(qty)
                    let deduction: Decimal = type_ == .percentage
                        ? productSubtotal * (value / 100)
                        : min(value, productSubtotal)
                    productDeduction += deduction
                }
                sum = max(0, sum - productDeduction)
            }
        }
        
        // Apply total round-up if enabled
        if event.isTotalRoundUp {
            return Decimal(ceil(NSDecimalNumber(decimal: sum).doubleValue))
        }
        return sum
    }
    
    // Calculate subtotal for a specific category
    func categorySubtotal(for categoryId: UUID, excludeProducts: Set<UUID> = []) -> Decimal {
        // If this category has an override, return that
        if let overridden = overriddenCategoryTotals[categoryId] {
            return overridden
        }
        
        // Check if there's an active Volume promo for this category
        let activePromo = event.promos.first(where: {
            $0.isActive &&
            !$0.isDeleted &&
            $0.mode == .typeList &&
            $0.category?.id == categoryId
        })
        
        // If there's a volume promo, calculate promo pricing
        if let promo = activePromo {
            // Volume mode
            // Get all promo-eligible products (isPromo = true) in cart for this category
            var promoEligibleQty = 0
            var promoEligibleProducts: [(product: Product, qty: Int)] = []
            var nonPromoSum: Decimal = 0
            
            for (productId, qty) in cart {
                guard qty > 0,
                      !excludeProducts.contains(productId),  // Skip combo products
                      let product = event.products.first(where: { $0.id == productId }),
                      product.category?.id == categoryId else { continue }
                
                if product.isPromo {
                    promoEligibleQty += qty
                    promoEligibleProducts.append((product, qty))
                } else {
                    // Non-promo products use regular pricing
                    nonPromoSum += convertPrice(product.price) * Decimal(qty)
                }
            }
            
            
            // Build product quantities map for star products
            var productQuantities: [UUID: Int] = [:]
            for (product, qty) in promoEligibleProducts {
                productQuantities[product.id] = qty
            }
            
            // Calculate promo price and convert to transaction currency
            let promoPrice = calculatePromoPrice(promo: promo, quantity: promoEligibleQty, productQuantities: productQuantities)
            let convertedPromoPrice = convertAndRoundPromoPrice(promoPrice)
            
            // If promo price is 0 (e.g., only 1 item), fall back to regular pricing for promo-eligible products
            if convertedPromoPrice == 0 && promoEligibleQty > 0 {
                var regularPromoSum: Decimal = 0
                for (product, qty) in promoEligibleProducts {
                    regularPromoSum += convertPrice(product.price) * Decimal(qty)
                }
                return regularPromoSum + nonPromoSum
            }
            
            return convertedPromoPrice + nonPromoSum
        }
        
        // No promo - calculate regular pricing
        var sum: Decimal = 0
        for (productId, qty) in cart {
            if qty > 0,
               !excludeProducts.contains(productId),  // Skip combo products
               let product = event.products.first(where: { $0.id == productId }),
               product.category?.id == categoryId {
                sum += convertPrice(product.price) * Decimal(qty)
            }
        }
        return sum
    }
    
    // Calculate promo price based on quantity and promo tier/incremental pricing
    // Includes star product surcharges
    private func calculatePromoPrice(promo: Promo, quantity: Int, productQuantities: [UUID: Int] = [:]) -> Decimal {
        guard quantity >= 2 else {
            // Less than 2 items - no promo applicable, return 0
            return 0
        }
        
        var basePrice: Decimal = 0
        
        // 1. Check tier prices first (2 to maxQuantity)
        if quantity <= promo.maxQuantity, let tierPrice = promo.tierPrices[quantity] {
            basePrice = tierPrice
        }
        // 2. For quantities from (maxQuantity + 1) to 9
        else if quantity <= 9 {
            guard let incrementalPrice = promo.incrementalPrice8to9,
                  let maxTierPrice = promo.tierPrices[promo.maxQuantity] else {
                return 0
            }
            let extraItems = quantity - promo.maxQuantity
            basePrice = maxTierPrice + (incrementalPrice * Decimal(extraItems))
        }
        // 3. For quantities 10+
        else if let incrementalPrice8to9 = promo.incrementalPrice8to9,
                let incrementalPrice10Plus = promo.incrementalPrice10Plus,
                let maxTierPrice = promo.tierPrices[promo.maxQuantity] {
            // Calculate price up to 9 items
            let priceAt9 = maxTierPrice + (incrementalPrice8to9 * Decimal(9 - promo.maxQuantity))
            // Add incremental for items beyond 9
            let extraItemsFrom10 = quantity - 9
            basePrice = priceAt9 + (incrementalPrice10Plus * Decimal(extraItemsFrom10))
        } else {
            return 0
        }
        
        // Add star product surcharges
        var starSurcharge: Decimal = 0
        for (productId, extraCost) in promo.starProducts {
            if let qty = productQuantities[productId], qty > 0 {
                starSurcharge += extraCost * Decimal(qty)
            }
        }
        
        return basePrice + starSurcharge
    }
    
    // Calculate combo promo price
    private func calculateComboPrice(promo: Promo, cart: [UUID: Int]) -> Decimal {
        guard !promo.comboProducts.isEmpty,
              let comboPrice = promo.comboPrice else { return 0 }
        
        // Find minimum quantity across combo products in cart
        var minQty = Int.max
        for productId in promo.comboProducts {
            let qty = cart[productId] ?? 0
            if qty == 0 { return 0 }  // Missing product, no combo
            minQty = min(minQty, qty)
        }
        
        guard minQty > 0 && minQty < Int.max else { return 0 }
        
        // Price = (number of combos × combo price) + leftover items at natural price
        var total = Decimal(minQty) * comboPrice
        
        // Add leftover items
        for productId in promo.comboProducts {
            let qty = cart[productId] ?? 0
            let leftover = qty - minQty
            
            if leftover > 0,
               let product = event.products.first(where: { $0.id == productId }) {
                total += convertPrice(product.price) * Decimal(leftover)
            }
        }
        
        return total
    }
    
    // Calculate prorated unit price for a product
    func proratedUnitPrice(for productId: UUID, quantity: Int) -> Decimal {
        guard let product = event.products.first(where: { $0.id == productId }) else {
            return 0
        }
        
        let originalPrice = convertPrice(product.price)
        
        // Check if general total is overridden
        if let overriddenGeneralTotal = overriddenTotal {
            // Calculate original total
            let originalTotal = calculateOriginalTotal()
            guard originalTotal > 0 else { return originalPrice }
            
            // Calculate percentage of this product in original total
            let productOriginalSubtotal = originalPrice * Decimal(quantity)
            let percentage = productOriginalSubtotal / originalTotal
            
            // Apply percentage to overridden total
            let proratedSubtotal = overriddenGeneralTotal * percentage
            return proratedSubtotal / Decimal(quantity)
        }
        
        // Check if this product's category has an override
        if let categoryId = product.category?.id,
           let overriddenCategoryTotal = overriddenCategoryTotals[categoryId] {
            // Calculate original category total
            let originalCategoryTotal = calculateOriginalCategoryTotal(categoryId: categoryId)
            guard originalCategoryTotal > 0 else { return originalPrice }
            
            // Calculate percentage of this product in category
            let productOriginalSubtotal = originalPrice * Decimal(quantity)
            let percentage = productOriginalSubtotal / originalCategoryTotal
            
            // Apply percentage to overridden category total
            let proratedSubtotal = overriddenCategoryTotal * percentage
            return proratedSubtotal / Decimal(quantity)
        }
        
        // Check if this product is part of any active combo promo
        let activeComboPromos = event.promos.filter {
            $0.isActive && !$0.isDeleted && $0.mode == .combo
        }
        
        for comboPromo in activeComboPromos {
            if product.isPromo,
               comboPromo.comboProducts.contains(productId),
               let _ = comboPromo.comboPrice {
                
                // Build combo cart
                var comboCart: [UUID: Int] = [:]
                var naturalComboTotal: Decimal = 0
                
                for prodId in comboPromo.comboProducts {
                    let qty = cart[prodId] ?? 0
                    if qty > 0, let p = event.products.first(where: { $0.id == prodId }), p.isPromo {
                        comboCart[prodId] = qty
                        naturalComboTotal += convertPrice(p.price) * Decimal(qty)
                    }
                }
                
                // Check if combo is complete
                let allProductsPresent = comboPromo.comboProducts.allSatisfy { comboCart[$0] ?? 0 > 0 }
                
                if allProductsPresent && naturalComboTotal > 0 {
                    // Get combo total price
                    let comboTotal = calculateComboPrice(promo: comboPromo, cart: comboCart)
                    
                    // Prorate based on natural price percentage
                    let productNaturalSubtotal = originalPrice * Decimal(quantity)
                    let percentage = productNaturalSubtotal / naturalComboTotal
                    let proratedSubtotal = comboTotal * percentage
                    
                    return proratedSubtotal / Decimal(quantity)
                }
            }
        }
        
        // Check if this product is part of any active N x M promo
        let activeNxMPromos = event.promos.filter {
            $0.isActive && !$0.isDeleted && $0.mode == .nxm
        }
        
        for nxmPromo in activeNxMPromos {
            guard let n = nxmPromo.nxmN, let m = nxmPromo.nxmM,
                  n > m && m >= 1,
                  product.isPromo,
                  nxmPromo.nxmProducts.contains(productId) else {
                continue
            }
            
            // Group eligible products by their price
            var priceGroups: [Decimal: Int] = [:]
            var totalEligibleQty = 0
            
            for prodId in nxmPromo.nxmProducts {
                let qty = cart[prodId] ?? 0
                if qty > 0, let p = event.products.first(where: { $0.id == prodId }), p.isPromo {
                    let convertedPrice = convertPrice(p.price)
                    priceGroups[convertedPrice, default: 0] += qty
                    totalEligibleQty += qty
                }
            }
            
            // Get this product's converted price
            let thisPrice = convertPrice(product.price)
            
            // Get quantity in this product's price group
            guard let priceGroupQty = priceGroups[thisPrice], priceGroupQty > 0 else {
                continue
            }
            
            // Calculate discount for this price group
            let completeSets = priceGroupQty / n
            let remainder = priceGroupQty % n
            let itemsPaidFor = (completeSets * m) + remainder
            
            // Calculate discounted total for this price group
            let priceGroupTotal = thisPrice * Decimal(itemsPaidFor)
            
            // Prorate based on this product's quantity within its price group
            let proratedSubtotal = priceGroupTotal * Decimal(quantity) / Decimal(priceGroupQty)
            
            return proratedSubtotal / Decimal(quantity)
        }
        
        // Check if this product's category has an active promo
        if let categoryId = product.category?.id,
           product.isPromo {  // Only prorate if product is promo-eligible
            let activePromo = event.promos.first(where: {
                $0.isActive &&
                !$0.isDeleted &&
                $0.mode == .typeList &&
                $0.category?.id == categoryId
            })
            
            if let promo = activePromo {
                // Calculate total promo-eligible quantity and products
                var promoEligibleQty = 0
                var naturalCategoryTotal: Decimal = 0
                
                for (productId, qty) in cart {
                    guard qty > 0,
                          let p = event.products.first(where: { $0.id == productId }),
                          p.category?.id == categoryId else { continue }
                    
                    if p.isPromo {
                        promoEligibleQty += qty
                        naturalCategoryTotal += convertPrice(p.price) * Decimal(qty)
                    }
                }
                
                
                // Build product quantities map for star products
                var productQuantities: [UUID: Int] = [:]
                for (productId, qty) in cart {
                    guard qty > 0,
                          let p = event.products.first(where: { $0.id == productId }),
                          p.category?.id == categoryId,
                          p.isPromo else { continue }
                    productQuantities[productId] = qty
                }
                
                // Get promo price for this quantity and convert to transaction currency
                let promoPrice = calculatePromoPrice(promo: promo, quantity: promoEligibleQty, productQuantities: productQuantities)
                let convertedPromoPrice = convertAndRoundPromoPrice(promoPrice)
                
                guard convertedPromoPrice > 0, naturalCategoryTotal > 0 else {
                    return originalPrice
                }
                
                // Calculate this product's percentage of natural category total
                let productNaturalSubtotal = originalPrice * Decimal(quantity)
                let percentage = productNaturalSubtotal / naturalCategoryTotal
                
                // Apply percentage to converted promo price
                let proratedSubtotal = convertedPromoPrice * percentage
                return proratedSubtotal / Decimal(quantity)
            }
        }
        
        // No override or promo, return original price
        return originalPrice
    }
    
    // Calculate original total without any overrides
    func calculateOriginalTotal() -> Decimal {
        var sum: Decimal = 0
        for (id, qty) in cart {
            if qty > 0, let product = event.products.first(where: { $0.id == id }) {
                sum += convertPrice(product.price) * Decimal(qty)
            }
        }
        return sum
    }
    
    // Calculate original category total without override
    func calculateOriginalCategoryTotal(categoryId: UUID) -> Decimal {
        var sum: Decimal = 0
        for (productId, qty) in cart {
            if qty > 0,
               let product = event.products.first(where: { $0.id == productId }),
               product.category?.id == categoryId {
                sum += convertPrice(product.price) * Decimal(qty)
            }
        }
        return sum
    }
    
    // Helper to convert prices using exchange rates
    // NO ROUNDING - prices are always converted using the exchange rate
    private func convertPrice(_ price: Decimal) -> Decimal {
        return price * rate
    }
    
    // Helper to convert promo prices using exchange rates
    // NO ROUNDING - promo prices are always converted using the exchange rate
    private func convertAndRoundPromoPrice(_ price: Decimal) -> Decimal {
        return price * rate
    }
    
    var availablePaymentMethods: [PaymentMethodOption] {
        // Decode payment methods from JSON Data
        guard let data = event.paymentMethodsData,
              let methods = try? JSONDecoder().decode([PaymentMethodOption].self, from: data) else {
            return []
        }
        
        // Find current currency UUID
        guard let currentCurrency = event.currencies.first(where: { $0.code == currentCurrencyCode }) else {
            return []
        }
        
        // Filter enabled payment methods that support this currency
        return methods.filter { method in
            method.isEnabled && method.enabledCurrencies.contains(currentCurrency.id)
        }
    }
    
    // Available Currencies (Only enabled ones from new model)
    var availableCurrencies: [String] {
        // Use new currencies model if available, fallback to old model for migration
        if !event.currencies.isEmpty {
            return event.currencies
                .filter { $0.isEnabled }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { $0.code }
        } else {
            // Fallback to old model
            var codes = Set([event.currencyCode])
            event.rates.forEach { codes.insert($0.currencyCode) }
            return Array(codes).sorted()
        }
    }
    
    
    // Computed properties
    private var effectiveCompanyName: String {
        if let companyName = event.companyName, !companyName.isEmpty {
            return companyName
        }
        return event.stripeCompanyName ?? ""
    }
    
    // MARK: - Initialization
    
    @ViewBuilder
    private var productPagerView: some View {
        if activeCategories.isEmpty {
            // No enabled categories - show all products
            ProductListView(
                category: nil,
                products: event.products.filter { $0.isActive && !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder },
                cart: $cart,
                rate: rate,
                currencyCode: currentCurrencyCode,
                event: event,
                defaultBackgroundColor: event.defaultProductBackgroundColor
            )
        } else if !event.areCategoriesEnabled {
            // Single mode - only one category enabled, show simple UX without TabView
            let category = activeCategories[0]
            ProductListView(
                category: category,
                products: event.products.filter { $0.category == category && $0.isActive && !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder },
                cart: $cart,
                rate: rate,
                currencyCode: currentCurrencyCode,
                event: event
            )
        } else {
            // Multiple mode - show TabView pager for multiple categories
            TabView(selection: $selectedTab) {
                ForEach(Array(activeCategories.enumerated()), id: \.element.id) { index, category in
                    ProductListView(
                        category: category,
                        products: event.products.filter { $0.category == category && $0.isActive && !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder },
                        cart: $cart,
                        rate: rate,
                        currencyCode: currentCurrencyCode,
                        event: event
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: selectedTab)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            // 1. Top Bar
            EventInfoHeader(
                event: event,
                userFullName: authService.currentUser?.fullName ?? "Operator",
                onQuit: onQuit
            )
            .zIndex(1)
            
            // 2. Table Headers
            PanelTableHeaderView()
            
            // 3. Products Pager - fixed height based on mode
            productPagerView
                .frame(height: event.areCategoriesEnabled ? 310 : 396) // 7 rows for multi, 9 for single @ 44pt each
                .disabled(event.isLocked)
                .opacity(event.isLocked ? 0.5 : 1.0)
            
            // 4. Spacer to ensure products touch footer
            Spacer(minLength: 0)
            
            // 5. Footer
            PanelFooterView(
                activeCategories: activeCategories,
                event: event,
                currentCurrencyCode: $currentCurrencyCode,
                derivedTotal: derivedTotal,
                note: $note,
                activeDiscountPromoIds: $activeDiscountPromoIds,
                categories: event.categories,
                products: event.products,
                cart: cart,
                rate: rate,
                overriddenTotal: $overriddenTotal,
                overriddenCategoryTotals: $overriddenCategoryTotals,
                showingOverrideSheet: $showingOverrideSheet,
                overrideTarget: $overrideTarget,
                overrideInputText: $overrideInputText,
                calculateOriginalTotal: calculateOriginalTotal,
                calculateOriginalCategoryTotal: calculateOriginalCategoryTotal,
                categorySubtotal: { categoryId in categorySubtotal(for: categoryId) },
                onClear: {
                    withAnimation {
                        showingClearConfirmation = true
                    }
                },
                onCheckout: {
                    showingPaymentMethodSheet = true
                }
            )
            .disabled(event.isLocked)
            .opacity(event.isLocked ? 0.5 : 1.0)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .overlay(
            VStack {
                if showingTransactionNotification {
                    CountdownNotificationView(text: "Transaction Saved")
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 20)
                }
                Spacer()
            }
            .animation(.spring(response: 0.3), value: showingTransactionNotification)
        )
        .padding(.bottom, keyboardHeight)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .onAppear {
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardHeight = keyboardFrame.height
                }
            }
            
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                keyboardHeight = 0
            }
        }
        .alert("Clear Cart?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) {
                cart.removeAll()
                note = ""
                activeDiscountPromoIds.removeAll()
                overriddenTotal = nil
                overriddenCategoryTotals.removeAll()
            }
            Button("Cancel", role: .cancel) { }
        }


        .sheet(isPresented: $showingPaymentMethodSheet) {
            PaymentMethodSelectionSheet(
                availableMethods: availablePaymentMethods,
                currentCurrency: currentCurrencyCode,
                derivedTotal: derivedTotal,
                onSelect: { methodOption in
                    self.selectedPaymentMethod = methodOption.toPaymentMethod()
                    showingPaymentMethodSheet = false
                    
                    selectedMethodOption = methodOption
                        
                        // Check icon-based features FIRST
                        // Some icons (like phone.fill for Bizum) convert to .other and can be caught by Stripe logic
                        
                        // 1. Bizum (phone icon)
                        if methodOption.icon.contains("phone") {
                            if let phoneNumber = event.bizumPhoneNumber, !phoneNumber.isEmpty {
                                showingBizumPayment = true
                            } else {
                                processCheckout()
                            }
                        }
                        // 2. Stripe QR (qrcode icon with Stripe provider)
                        else if methodOption.icon.contains("qrcode") && methodOption.enabledProviders.contains("stripe") && event.stripeIntegrationEnabled {
                            showingStripeQRPayment = true
                        }
                        // 3. Stripe Card (creditcard icon with Stripe provider)
                        else if methodOption.icon.contains("creditcard") && methodOption.enabledProviders.contains("stripe") && event.stripeIntegrationEnabled {
                            showingStripeCardPayment = true
                        }
                        // 4. Everything else - manual payment
                        else {
                            processCheckout()
                        }

                },
                onCancel: {
                    showingPaymentMethodSheet = false
                }
            )
            .presentationDetents([
                .height(min(CGFloat(200 + (availablePaymentMethods.count * 80)), 600))
            ])
        }
        .sheet(isPresented: $showingOverrideSheet) {
            let symbol = event.currencies.first(where: { $0.code == currentCurrencyCode })?.symbol ?? currentCurrencyCode
            OverrideInputSheet(
                target: overrideTarget,
                currentTotal: derivedTotal,
                currencySymbol: symbol,
                inputText: $overrideInputText,
                onApply: applyOverride,
                onClear: clearOverride,
                onDismiss: { showingOverrideSheet = false }
            )
            .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showingStripeCardPayment) {
            if let backendURL = event.stripeBackendURL {
                let txnRef = generateTransactionRef()
                StripeTapToPayView(
                    amount: derivedTotal,
                    currency: currentCurrencyCode,
                    description: paymentDescription(txnRef: txnRef),
                    backendURL: backendURL,
                    locationId: event.stripeLocationId ?? "",
                    onSuccess: { paymentIntentId in
                        // Store payment info and show receipt prompt
                        pendingPaymentIntentId = paymentIntentId
                        pendingTxnRef = txnRef
                        showingStripeCardPayment = false
                        showingReceiptPrompt = true
                    },
                    onCancel: {
                        showingStripeCardPayment = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingTapToPayEducation) {
            NavigationView {
                if let userId = authService.currentUser?.id.uuidString {
                    TapToPayEducationView(userId: userId)
                }
            }
        }
        .sheet(isPresented: $showingStripeQRPayment) {
            if let backendURL = event.stripeBackendURL {
                let txnRef = generateTransactionRef()
                StripeQRPaymentView(
                    amount: derivedTotal,
                    currency: currentCurrencyCode,
                    description: paymentDescription(txnRef: txnRef),
                    companyName: effectiveCompanyName,
                    lineItems: stripeLineItems().isEmpty ? nil : stripeLineItems(),
                    backendURL: backendURL,
                    onSuccess: { sessionId in
                        processCheckoutWithStripe(paymentIntentId: nil, sessionId: sessionId, txnRef: txnRef)
                    },
                    onCancel: {
                        showingStripeQRPayment = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingBizumPayment) {
            if let phoneNumber = event.bizumPhoneNumber {
                let symbol = event.currencies.first(where: { $0.code == currentCurrencyCode })?.symbol ?? currentCurrencyCode
                BizumPaymentView(
                    amount: derivedTotal,
                    currency: symbol,
                    phoneNumber: phoneNumber,
                    onComplete: {
                        processCheckout()
                        showingBizumPayment = false
                    },
                    onCancel: {
                        showingBizumPayment = false
                    }
                )
            }
        }
        .alert("Need Receipt?", isPresented: $showingReceiptPrompt) {
            Button("Yes") {
                showingReceiptEmailSheet = true
            }
            Button("No") {
                // Process checkout without email
                if let intentId = pendingPaymentIntentId, let txnRef = pendingTxnRef {
                    processCheckoutWithStripe(paymentIntentId: intentId, sessionId: nil, txnRef: txnRef)
                    pendingPaymentIntentId = nil
                    pendingTxnRef = nil
                }
            }
        } message: {
            Text("Would the customer like an email receipt?")
        }
        .sheet(isPresented: $showingReceiptEmailSheet) {
            if let intentId = pendingPaymentIntentId,
               let backendURL = event.stripeBackendURL,
               let txnRef = pendingTxnRef {
                ReceiptEmailSheet(
                    paymentIntentId: intentId,
                    backendURL: backendURL,
                    onComplete: { customerEmail in
                        showingReceiptEmailSheet = false
                        pendingReceiptEmail = customerEmail
                        processCheckoutWithStripe(paymentIntentId: intentId, sessionId: nil, txnRef: txnRef)
                        pendingPaymentIntentId = nil
                        pendingTxnRef = nil
                        pendingReceiptEmail = nil
                    },
                    onCancel: {
                        showingReceiptEmailSheet = false
                        processCheckoutWithStripe(paymentIntentId: intentId, sessionId: nil, txnRef: txnRef)
                        pendingPaymentIntentId = nil
                        pendingTxnRef = nil
                    }
                )
            }
        }
        // Manual payment receipt prompt (Cash, Bizum, Transfer)
        .alert("Need Receipt?", isPresented: $showingManualReceiptPrompt) {
            Button("Yes") {
                showingManualReceiptEmailSheet = true
            }
            Button("No") {
                // Process checkout without receipt
                completeManualCheckout(receiptEmail: nil)
            }
        } message: {
            Text("Would the customer like an email receipt?")
        }
        .sheet(isPresented: $showingManualReceiptEmailSheet) {
            SimpleEmailSheet(
                onComplete: { customerEmail in
                    showingManualReceiptEmailSheet = false
                    // Complete checkout with receipt email
                    completeManualCheckout(receiptEmail: customerEmail)
                },
                onCancel: {
                    showingManualReceiptEmailSheet = false
                    // Complete without receipt
                    completeManualCheckout(receiptEmail: nil)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
    }
    
    // Helper to build line items for Stripe checkout
    private func stripeLineItems() -> [[String: Any]] {
        let activePromos = event.promos.filter { $0.isActive }
        let hasActivePromos = !activePromos.isEmpty && event.arePromosEnabled
        
        if hasActivePromos {
            // Calculate natural total (without promos)
            var naturalTotal: Decimal = 0
            let itemsWithPrices: [(name: String, naturalPrice: Decimal, quantity: Int)] = cart.compactMap { (productId, quantity) in
                guard quantity > 0, let product = event.products.first(where: { $0.id == productId }) else {
                    return nil
                }
                let convertedPrice = convertPrice(product.price)
                naturalTotal += convertedPrice * Decimal(quantity)
                return (product.name, convertedPrice, quantity)
            }
            
            // Calculate discount ratio: finalTotal / naturalTotal
            let discountRatio = naturalTotal > 0 ? derivedTotal / naturalTotal : 1
            
            // Pro-rate each item's price by the discount ratio
            return itemsWithPrices.map { item in
                let promoAdjustedPrice = item.naturalPrice * discountRatio
                return [
                    "name": item.name,
                    "price": NSDecimalNumber(decimal: promoAdjustedPrice).doubleValue,
                    "quantity": item.quantity
                ]
            }
        } else {
            // No promos - send items at natural prices
            return cart.compactMap { (productId, quantity) in
                guard quantity > 0, let product = event.products.first(where: { $0.id == productId }) else {
                    return nil
                }
                return [
                    "name": product.name,
                    "price": NSDecimalNumber(decimal: convertPrice(product.price)).doubleValue,
                    "quantity": quantity
                ]
            }
        }
    }
    
    // Generate a short transaction reference (e.g., 1A2B3C)
    // Uses 6 UUID chars for better uniqueness across multiple devices
    private func generateTransactionRef() -> String {
        let count = event.transactions.count + 1
        let uuid = UUID().uuidString.prefix(6).uppercased()
        return "\(count)\(uuid)"
    }
    
    // Build payment description with company, transaction ref, and items
    private func paymentDescription(txnRef: String) -> String {
        let companyName = effectiveCompanyName.isEmpty ? "Payment" : effectiveCompanyName
        let items = stripeLineItems()
        
        if items.isEmpty {
            return "\(companyName) | \(txnRef)"
        }
        
        let itemsList = items.compactMap { item -> String? in
            guard let name = item["name"] as? String,
                  let qty = item["quantity"] as? Int else {
                return nil
            }
            return "\(qty)x \(name)"
        }.joined(separator: ", ")
        
        return "\(companyName) | \(txnRef) | \(itemsList)"
    }
    
    func processCheckout() {
        guard !event.isLocked else { return }
        guard cart.values.contains(where: { $0 > 0 }) else { return }
        
        //Check if receipt prompt should be shown
        if ReceiptService.shouldShowReceiptPrompt(for: selectedPaymentMethod, event: event) {
            // Store pending checkout data
            pendingManualCheckoutPaymentMethod = selectedPaymentMethod
            // Show receipt prompt
            showingManualReceiptPrompt = true
            return
        }
        
        // No receipt prompt - process immediately
        completeManualCheckout(receiptEmail: nil)
    }
    
    // Helper to complete manual checkout (with or without receipt)
    func completeManualCheckout(receiptEmail: String?) {
        let txnRef = generateTransactionRef()
        
        let transaction = Transaction(
            totalAmount: derivedTotal,
            currencyCode: currentCurrencyCode,
            note: note.isEmpty ? nil : note,
            paymentMethod: pendingManualCheckoutPaymentMethod ?? selectedPaymentMethod,
            paymentMethodIcon: selectedMethodOption?.icon,
            transactionRef: txnRef,
            receiptEmail: receiptEmail
        )
        
        for (id, qty) in cart {
            if qty > 0, let product = event.products.first(where: { $0.id == id }) {
                // Use prorated price if there's an override, otherwise use converted price
                let basePrice = proratedUnitPrice(for: id, quantity: qty)
                let finalPrice = discountAdjustedUnitPrice(for: id, quantity: qty, baseUnitPrice: basePrice)
                let line = LineItem(
                    productName: product.name,
                    quantity: qty,
                    unitPrice: finalPrice,
                    subgroup: product.subgroup
                )
                line.product = product
                transaction.lineItems.append(line)
            }
        }
        
        event.transactions.append(transaction)
        
        // Deduct stock quantities if stock control is enabled
        if event.isStockControlEnabled {
            for lineItem in transaction.lineItems {
                if let product = lineItem.product, product.stockQty != nil {
                    product.stockQty = max(0, (product.stockQty ?? 0) - lineItem.quantity)
                }
            }
        }
        
        // Send custom receipt if email provided and it's a custom receipt payment method
        if let email = receiptEmail,
           ReceiptService.usesCustomReceipt(paymentMethod: transaction.paymentMethod) {
            Task {
                let result = await ReceiptService.sendCustomReceipt(
                    transaction: transaction,
                    event: event,
                    email: email
                )
                if !result.success {
                    print("Failed to send receipt: \(result.error ?? "Unknown error")")
                }
            }
        }
        
        cart.removeAll()
        note = ""
        
        // Clear overrides after checkout
        overriddenTotal = nil
        overriddenCategoryTotals.removeAll()
        
        // Clear pending data
        pendingManualCheckoutPaymentMethod = nil
        
        // Show notification banner
        withAnimation {
            showingTransactionNotification = true
        }
        // Auto-dismiss after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    showingTransactionNotification = false
                }
            }
        }
    }
    
    func processCheckoutWithStripe(paymentIntentId: String?, sessionId: String?, txnRef: String) {
        guard !event.isLocked else { return }
        guard cart.values.contains(where: { $0 > 0 }) else { return }
        
        // Determine payment status
        let status = paymentIntentId != nil || sessionId != nil ? "succeeded" : "manual"
        
        let transaction = Transaction(
            totalAmount: derivedTotal,
            currencyCode: currentCurrencyCode,
            note: note.isEmpty ? nil : note,
            paymentMethod: selectedPaymentMethod,
            paymentMethodIcon: selectedMethodOption?.icon,
            transactionRef: txnRef,
            stripePaymentIntentId: paymentIntentId,
            stripeSessionId: sessionId,
            paymentStatus: status,
            receiptEmail: pendingReceiptEmail
        )
        
        for (id, qty) in cart {
            if qty > 0, let product = event.products.first(where: { $0.id == id }) {
                // Use prorated price if there's an override, otherwise use converted price
                let basePrice = proratedUnitPrice(for: id, quantity: qty)
                let finalPrice = discountAdjustedUnitPrice(for: id, quantity: qty, baseUnitPrice: basePrice)
                let line = LineItem(
                    productName: product.name,
                    quantity: qty,
                    unitPrice: finalPrice,
                    subgroup: product.subgroup
                )
                line.product = product
                transaction.lineItems.append(line)
            }
        }
        
        event.transactions.append(transaction)
        
        // Deduct stock quantities if stock control is enabled
        if event.isStockControlEnabled {
            for lineItem in transaction.lineItems {
                if let product = lineItem.product, product.stockQty != nil {
                    product.stockQty = max(0, (product.stockQty ?? 0) - lineItem.quantity)
                }
            }
        }
        
        cart.removeAll()
        note = ""
        
        // Clear overrides after checkout
        overriddenTotal = nil
        overriddenCategoryTotals.removeAll()
        
        // Close Stripe sheets
        showingStripeCardPayment = false
        showingStripeQRPayment = false
        
        // Show notification banner
        withAnimation {
            showingTransactionNotification = true
        }
        // Auto-dismiss after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    showingTransactionNotification = false
                }
            }
        }
    }
    
    /// Returns the unit price for a line item after applying any active discount promos.
    /// - Total-mode discounts: distributed proportionally across all line items by their share of the pre-discount total.
    /// - Product-mode discounts: applied directly to the matching product's unit price.
    func discountAdjustedUnitPrice(for productId: UUID, quantity: Int, baseUnitPrice: Decimal) -> Decimal {
        let activeDiscountPromos = event.promos.filter {
            $0.isActive && !$0.isDeleted && $0.mode == .discount && activeDiscountPromoIds.contains($0.id)
        }
        guard !activeDiscountPromos.isEmpty else { return baseUnitPrice }
        
        // Compute the pre-discount total (sum of all base unit prices × qty)
        var preDiscountTotal: Decimal = 0
        for (id, qty) in cart {
            if qty > 0 {
                preDiscountTotal += proratedUnitPrice(for: id, quantity: qty) * Decimal(qty)
            }
        }
        guard preDiscountTotal > 0 else { return baseUnitPrice }
        
        // Separate total-mode and product-mode promos
        var totalModeDiscount: Decimal = 0
        var productModeUnitPrice: Decimal = baseUnitPrice
        var hasProductModeDiscount = false
        
        for discountPromo in activeDiscountPromos {
            guard let value = discountPromo.discountValue, value > 0 else { continue }
            let target = DiscountTarget(rawValue: discountPromo.discountTarget ?? "total") ?? .total
            let type_ = DiscountType(rawValue: discountPromo.discountType ?? "percentage") ?? .percentage
            
            if target == .total {
                let deduction: Decimal = type_ == .percentage
                    ? preDiscountTotal * (value / 100)
                    : value
                totalModeDiscount += min(deduction, preDiscountTotal)
            } else {
                // Product-specific: only discount selected products
                let selectedIds = (try? JSONDecoder().decode(Set<UUID>.self, from: discountPromo.discountProductIds ?? Data())) ?? []
                if selectedIds.contains(productId) {
                    let productSubtotal = productModeUnitPrice * Decimal(quantity)
                    let deduction: Decimal = type_ == .percentage
                        ? productSubtotal * (value / 100)
                        : min(value, productSubtotal)
                    let discountedSubtotal = max(0, productSubtotal - deduction)
                    productModeUnitPrice = discountedSubtotal / Decimal(quantity)
                    hasProductModeDiscount = true
                }
            }
        }
        
        // Apply product-mode discounts first (already computed above)
        var result = hasProductModeDiscount ? productModeUnitPrice : baseUnitPrice
        
        // Then distribute total-mode discount proportionally by this product's share
        if totalModeDiscount > 0 {
            let thisProductSubtotal = result * Decimal(quantity)
            let share = preDiscountTotal > 0 ? (baseUnitPrice * Decimal(quantity)) / preDiscountTotal : 0
            let productDiscount = totalModeDiscount * share
            let discountedSubtotal = max(0, thisProductSubtotal - productDiscount)
            result = discountedSubtotal / Decimal(quantity)
        }
        
        return result
    }
    
    func applyOverride() {
        guard let target = overrideTarget,
              let value = Decimal(string: overrideInputText.replacingOccurrences(of: ",", with: "")),
              value > 0 else {
            showingOverrideSheet = false
            return
        }
        
        switch target {
        case .generalTotal:
            overriddenTotal = value
            // Clear category overrides when general total is set
            overriddenCategoryTotals.removeAll()
        case .categorySubtotal(let categoryId):
            overriddenCategoryTotals[categoryId] = value
            // Clear general override if any category is overridden
            overriddenTotal = nil
        }
        
        showingOverrideSheet = false
    }
    
    func clearOverride() {
        guard let target = overrideTarget else {
            showingOverrideSheet = false
            return
        }
        
        switch target {
        case .generalTotal:
            overriddenTotal = nil
        case .categorySubtotal(let categoryId):
            overriddenCategoryTotals.removeValue(forKey: categoryId)
        }
        
        showingOverrideSheet = false
    }
}

// MARK: - Subviews

struct PanelTableHeaderView: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("PRODUCT")
                //.frame(maxWidth: .infinity, alignment: .leading)
                .frame(width: 120, alignment: .center)
                .padding(.leading, 10)
            Text("PRICE")
                .frame(width: 80, alignment: .center)
            Text("QTY")
                .frame(width: 50, alignment: .center)
                .padding(.leading, 10)
            Text("TOTAL")
                .frame(width: 80, alignment: .center)
            Text("ACTIONS")
                .frame(width: 85, alignment: .leading)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.gray)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

struct PanelFooterView: View {
    @FocusState private var isNotesFocused: Bool
    let activeCategories: [Category]
    @Bindable var event: Event
    @Binding var currentCurrencyCode: String
    let derivedTotal: Decimal
    @Binding var note: String
    @Binding var activeDiscountPromoIds: Set<UUID>
    
    let categories: [Category]
    let products: [Product]
    let cart: [UUID: Int]
    let rate: Decimal
    
    // Override state
    @Binding var overriddenTotal: Decimal?
    @Binding var overriddenCategoryTotals: [UUID: Decimal]
    @Binding var showingOverrideSheet: Bool
    @Binding var overrideTarget: OverrideTarget?
    @Binding var overrideInputText: String
    let calculateOriginalTotal: () -> Decimal
    let calculateOriginalCategoryTotal: (UUID) -> Decimal
    let categorySubtotal: (UUID) -> Decimal
    
    let onClear: () -> Void
    let onCheckout: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if event.areCategoriesEnabled {
                // MULTI-CATEGORY LAYOUT: 2-column with subtotals
                // Top section: 2-column layout
                HStack(alignment: .top, spacing: 12) {
                // LEFT COLUMN: Subtotals + Total stacked vertically
                VStack(alignment: .leading, spacing: 0) {
                    // Subtotals - show exactly 2 rows
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(activeCategories) { cat in
                                let catTotal = categorySubtotal(cat.id)
                                let originalCatTotal = calculateOriginalCategoryTotal(cat.id)
                                let isOverridden = overriddenCategoryTotals[cat.id] != nil
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(cat.name) Subtotal:")
                                            .font(.system(size: 15))
                                            .foregroundStyle(.black)
                                        if isOverridden {
                                            Text(currencySymbol(for: currentCurrencyCode) + originalCatTotal.formatted(.number.precision(.fractionLength(2))))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .strikethrough()
                                        }
                                    }
                                    Spacer()
                                    Text(currencySymbol(for: currentCurrencyCode) + catTotal.formatted(.number.precision(.fractionLength(2))))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(isOverridden ? .green : .black)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(hex: cat.hexColor))
                                .cornerRadius(8)
                                .onTapGesture {
                                    overrideTarget = .categorySubtotal(categoryId: cat.id)
                                    overrideInputText = catTotal.formatted(.number.precision(.fractionLength(2)))
                                    showingOverrideSheet = true
                                }
                            }
                        }
                    }
                    .frame(height: 120) // Reduced from 86 to show exactly 2 rows without peek
                    
                    Spacer(minLength: 0) // Push Total down
                    
                    // Total - aligned to center of 3rd currency button
                    let isGeneralOverridden = overriddenTotal != nil
                    let originalGeneralTotal = calculateOriginalTotal()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Total:")
                                .font(.system(size: 24, weight: .bold))
                            Spacer()
                            Text(currencySymbol(for: currentCurrencyCode) + derivedTotal.formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(isGeneralOverridden ? .green : .primary)
                        }
                        if isGeneralOverridden {
                            HStack {
                                Spacer()
                                Text(currencySymbol(for: currentCurrencyCode) + originalGeneralTotal.formatted(.number.precision(.fractionLength(2))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                            }
                        }
                    }
                    .onTapGesture {
                        overrideTarget = .generalTotal
                        overrideInputText = derivedTotal.formatted(.number.precision(.fractionLength(2)))
                        showingOverrideSheet = true
                    }
                    
                    //Spacer().frame(height: 16) // Push Total up to center with 3rd currency button
                }
                .frame(height: 156) // Match currency buttons column height (3 * 52)
                
                // RIGHT COLUMN: Currency buttons
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(event.currencies.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }, id: \.id) { currency in
                            Button(action: { currentCurrencyCode = currency.code }) {
                                Text(currency.symbol + " " + currency.code)
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 90, height: 50)
                                    .background(currentCurrencyCode == currency.code ? Color.blue : Color(UIColor.systemGray5))
                                    .foregroundStyle(currentCurrencyCode == currency.code ? .white : .primary)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .frame(width: 85, height: 170) // Fixed height to match left column
            }
            .padding(.top, 16) // Add top padding matching horizontal
            } else {
               // SINGLE-CATEGORY LAYOUT: Simpler, no subtotals
                // Total - full width
                let isGeneralOverridden = overriddenTotal != nil
                let originalGeneralTotal = calculateOriginalTotal()
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Total:")
                            .font(.system(size: 24, weight: .bold))
                        Spacer()
                        Text(currencySymbol(for: currentCurrencyCode) + derivedTotal.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(isGeneralOverridden ? .green : .primary)
                    }
                    if isGeneralOverridden {
                        HStack {
                            Spacer()
                            Text(currencySymbol(for: currentCurrencyCode) + originalGeneralTotal.formatted(.number.precision(.fractionLength(2))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .strikethrough()
                        }
                    }
                }
                .onTapGesture {
                    overrideTarget = .generalTotal
                    overrideInputText = derivedTotal.formatted(.number.precision(.fractionLength(2)))
                    showingOverrideSheet = true
                }
                .padding(.top, 16) // Add top padding
                
                // Currency buttons - horizontal scrolling
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(event.currencies.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }, id: \.id) { currency in
                                let buttonCount = CGFloat(min(event.currencies.filter { $0.isEnabled }.count, 3))
                                let totalSpacing = 10 * (buttonCount - 1)
                                let buttonWidth = (geometry.size.width - totalSpacing) / buttonCount
                                
                                Button(action: { currentCurrencyCode = currency.code }) {
                                    HStack(spacing: 4) {
                                        Text(currency.symbol)
                                            .font(.system(size: 18, weight: .bold))
                                        Text(currency.code)
                                            .font(.system(size: 18, weight: .bold))
                                    }
                                    .frame(width: buttonWidth, height: 40)
                                    .background(currentCurrencyCode == currency.code ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(currentCurrencyCode == currency.code ? .white : .primary)
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                }
                .frame(height: 40)
                .padding(.top, 16) // Add top padding
            }
            
            // Notes + Promo buttons row
            let discountPromos = event.promos.filter { $0.isActive && !$0.isDeleted && $0.mode == .discount }
            HStack(spacing: 8) {
                if !discountPromos.isEmpty {
                    // Promo buttons (left side, up to half width)
                    GeometryReader { geo in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                let count = CGFloat(min(discountPromos.count, 3))
                                let spacing = 6 * (count - 1)
                                let btnWidth = (geo.size.width - spacing) / count
                                ForEach(discountPromos) { promo in
                                    let isOn = activeDiscountPromoIds.contains(promo.id)
                                    Button(action: {
                                        if isOn {
                                            activeDiscountPromoIds.remove(promo.id)
                                        } else {
                                            activeDiscountPromoIds.insert(promo.id)
                                        }
                                    }) {
                                        Text(promo.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                            .frame(width: discountPromos.count <= 3 ? btnWidth : 90, height: 46)
                                            .background(isOn ? Color.green : Color(UIColor.systemGray5))
                                            .foregroundStyle(isOn ? .white : .primary)
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 46)
                    
                    // Notes field (right half)
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.gray.opacity(0.5))
                            .font(.system(size: 15))
                        TextField("Notes (optional)", text: $note)
                            .font(.system(size: 15))
                            .focused($isNotesFocused)
                            .submitLabel(.done)
                            .onSubmit { isNotesFocused = false }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    // No discount promos — full-width notes field
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.gray.opacity(0.5))
                            .font(.system(size: 15))
                        TextField("Notes (optional)", text: $note)
                            .font(.system(size: 15))
                            .focused($isNotesFocused)
                            .submitLabel(.done)
                            .onSubmit { isNotesFocused = false }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.top, 10)
            .scrollDismissesKeyboard(.interactively)
            
            // Action buttons - Clear 30%, Pay Now 70%
            let cartHasItems = cart.values.contains { $0 > 0 }
            GeometryReader { geometry in
                HStack(spacing: 10) {
                    Button(action: onClear) {
                        Text("Clear")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: geometry.size.width * 0.35 - 5, height: 46)
                            .background(cartHasItems ? Color.red : Color.gray)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!cartHasItems)
                    
                    Button(action: onCheckout) {
                        Text("Pay Now")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: geometry.size.width * 0.65 - 5, height: 46)
                            .background(cartHasItems ? Color.green : Color.gray)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!cartHasItems)
                }
            }
            .frame(height: 46)
            .padding(.top, 16) // Increased from 6 to 16
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 16) // Increased from 4 to 16 for space above nav tabs
        .background(Color(UIColor.systemGroupedBackground)) // Match table background
    }
    
    func calculateSubtotal(for category: Category) -> Decimal {
        var sum: Decimal = 0
        let categoryProducts = products.filter { $0.category == category }
        for prod in categoryProducts {
            if let qty = cart[prod.id], qty > 0 {
                sum += (prod.price * Decimal(qty))
            }
        }
        let converted = sum * rate
        // Apply total round-up if enabled
        if event.isTotalRoundUp {
            return Decimal(ceil(NSDecimalNumber(decimal: converted).doubleValue))
        }
        return converted
    }
    
    func currencySymbol(for code: String) -> String {
        // Use currency model symbol if available, fallback to currency code
        return event.currencies.first(where: { $0.code == code })?.symbol ?? code
    }
}

struct ProductListView: View {
    let category: Category?
    let products: [Product]
    @Binding var cart: [UUID: Int]
    let rate: Decimal
    let currencyCode: String
    let event: Event
    var defaultBackgroundColor: String? = nil

    // Stock warning toast state
    @State private var stockWarningText: String = ""
    @State private var showingStockWarning: Bool = false

    /// True when this product is fully out of stock (qty 0) and stock control is active
    private func isOutOfStock(_ product: Product) -> Bool {
        guard event.isStockControlEnabled, let qty = product.stockQty else { return false }
        return qty <= 0
    }

    /// Remaining available units for a product (stockQty minus what's already in cart)
    private func remainingStock(for product: Product) -> Int? {
        guard event.isStockControlEnabled, let stockQty = product.stockQty else { return nil }
        let inCart = cart[product.id] ?? 0
        return max(0, stockQty - inCart)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(products) { product in
                        let qty = cart[product.id] ?? 0
                        let convertedPrice = product.price * rate
                        let rowTotal = convertedPrice * Decimal(qty)
                        let outOfStock = isOutOfStock(product)

                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Text(product.name)
                                    .font(.system(size: 16))
                                    .lineLimit(2)
                                    .foregroundStyle(outOfStock ? Color.gray : Color.black)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 12)

                                Text(currencySymbol(for: currencyCode) + convertedPrice.formatted(.number.precision(.fractionLength(2))))
                                    .font(.system(size: 16))
                                    .foregroundStyle(outOfStock ? Color.gray : Color.black)
                                    .frame(width: 80, alignment: .trailing)

                                Text("\(qty)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(outOfStock ? Color.gray : Color.black)
                                    .frame(width: 40, alignment: .trailing)

                                Text(currencySymbol(for: currencyCode) + rowTotal.formatted(.number.precision(.fractionLength(2))))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(outOfStock ? Color.gray : Color.black)
                                    .frame(width: 80, alignment: .trailing)

                                HStack(spacing: 6) {
                                    Button {
                                        updateCart(id: product.id, delta: -1)
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: 32, height: 32)
                                            .background(Color.red)
                                            .foregroundStyle(.white)
                                            .clipShape(Circle())
                                    }

                                    Button {
                                        tryAddToCart(product: product)
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: 32, height: 32)
                                            .background(outOfStock ? Color.gray : Color.green)
                                            .foregroundStyle(.white)
                                            .clipShape(Circle())
                                    }
                                    .disabled(outOfStock)
                                }
                                .frame(width: 85, alignment: .center)
                            }
                            .frame(height: 44)
                            .opacity(outOfStock ? 0.5 : 1.0)

                            Divider()
                                .background(Color.white.opacity(0.3))
                        }
                    }
                }
                .background(
                    category.map { Color(hex: $0.hexColor) } ?? Color(hex: defaultBackgroundColor ?? "#FFFFFF")
                )
            }

            // Stock warning toast
            if showingStockWarning {
                Text(stockWarningText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.95))
                    .cornerRadius(10)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.3), value: showingStockWarning)
    }

    /// Attempts to add 1 unit to cart, showing a warning if stock would be exceeded
    private func tryAddToCart(product: Product) {
        if let remaining = remainingStock(for: product), remaining <= 0 {
            showStockWarning(for: product.name)
            return
        }
        updateCart(id: product.id, delta: 1)
    }

    private func showStockWarning(for productName: String) {
        stockWarningText = "Not enough units of \(productName) in stock"
        withAnimation {
            showingStockWarning = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation {
                    showingStockWarning = false
                }
            }
        }
    }

    func updateCart(id: UUID, delta: Int) {
        let current = cart[id] ?? 0
        let new = current + delta
        if new >= 0 {
            cart[id] = new
        }
    }

    func currencySymbol(for code: String) -> String {
        return event.currencies.first(where: { $0.code == code })?.symbol ?? code
    }
}


// MARK: - Override Input Sheet
struct OverrideInputSheet: View {
    let target: OverrideTarget?
    let currentTotal: Decimal
    let currencySymbol: String
    @Binding var inputText: String
    let onApply: () -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void
    
    @FocusState private var isInputFocused: Bool
    
    var title: String {
        guard let target = target else { return "Override Total" }
        switch target {
        case .generalTotal:
            return "Override Total"
        case .categorySubtotal:
            return "Override Category Subtotal"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.top)
            
            // Current value
            Text("Current: \(currencySymbol)\(currentTotal.formatted(.number.precision(.fractionLength(2))))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Input field
            HStack {
                Text(currencySymbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("New amount", text: $inputText)
                    .font(.title3)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: onClear) {
                    Text("Clear Override")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .cornerRadius(10)
                }
                
                Button(action: onApply) {
                    Text("Apply")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .onAppear {
            isInputFocused = true
        }
    }
}

// MARK: - Preview
#Preview("Panel with 4 Currencies & 4 Categories") {
    @Previewable @State var sampleEvent: Event = {
        let event = Event(name: "Test Event", date: Date(), currencyCode: "GBP")
        
        // Add 4 currencies
        let gbp = Currency(code: "GBP", symbol: "£", name: "British Pound", rate: 1.0, isMain: true, isEnabled: true, sortOrder: 0)
        let usd = Currency(code: "USD", symbol: "$", name: "US Dollar", rate: 1.27, isEnabled: true, sortOrder: 1)
        let eur = Currency(code: "EUR", symbol: "€", name: "Euro", rate: 1.17, isEnabled: true, sortOrder: 2)
        let jpy = Currency(code: "JPY", symbol: "¥", name: "Japanese Yen", rate: 189.5, isEnabled: true, sortOrder: 3)
        event.currencies = [gbp, usd, eur, jpy]
        
        // Add 4 categories
        let apps = Category(name: "Apps", hexColor: "#B3E5FC", isEnabled: true, sortOrder: 0)
        let stuff = Category(name: "Stuff", hexColor: "#FFF9C4", isEnabled: true, sortOrder: 1)
        let music = Category(name: "Music", hexColor: "#C8E6C9", isEnabled: true, sortOrder: 2)
        let food = Category(name: "Food", hexColor: "#FFCCBC", isEnabled: true, sortOrder: 3)
        event.categories = [apps, stuff, music, food]
        
        // Add sample products - 7 for Apps, 12 for Stuff
        let p1 = Product(name: "AnyWeb", price: 30.00, sortOrder: 0)
        p1.category = apps
        let p2 = Product(name: "Pulse2 Pro", price: 50.00, sortOrder: 1)
        p2.category = apps
        let p3 = Product(name: "iFlix", price: 25.00, sortOrder: 2)
        p3.category = apps
        let p4 = Product(name: "Syncro", price: 35.00, sortOrder: 3)
        p4.category = apps
        let p5 = Product(name: "Contactum", price: 20.00, sortOrder: 4)
        p5.category = apps
        let p6 = Product(name: "Unlock", price: 30.00, sortOrder: 5)
        p6.category = apps
        let p7 = Product(name: "AnyWeb 2", price: 30.00, sortOrder: 6)
        p7.category = apps
        
        let s1 = Product(name: "Cards x 20", price: 10.00, sortOrder: 0)
        s1.category = stuff
        let s2 = Product(name: "Cards x 50", price: 20.00, sortOrder: 1)
        s2.category = stuff
        let s3 = Product(name: "Cards x 100", price: 40.00, sortOrder: 2)
        s3.category = stuff
        let s4 = Product(name: "Cards x 200", price: 70.00, sortOrder: 3)
        s4.category = stuff
        let s5 = Product(name: "Block A4", price: 20.00, sortOrder: 4)
        s5.category = stuff
        let s6 = Product(name: "Block A6", price: 15.00, sortOrder: 5)
        s6.category = stuff
        let s7 = Product(name: "Block A7", price: 10.00, sortOrder: 6)
        s7.category = stuff
        let s8 = Product(name: "Pen Blue", price: 2.00, sortOrder: 7)
        s8.category = stuff
        let s9 = Product(name: "Pen Black", price: 2.00, sortOrder: 8)
        s9.category = stuff
        let s10 = Product(name: "Pen Red", price: 2.00, sortOrder: 9)
        s10.category = stuff
        let s11 = Product(name: "Marker Pack", price: 8.00, sortOrder: 10)
        s11.category = stuff
        let s12 = Product(name: "Eraser", price: 1.50, sortOrder: 11)
        s12.category = stuff
        
        let m1 = Product(name: "Vinyl Record", price: 25.00, sortOrder: 0)
        m1.category = music
        
        let f1 = Product(name: "Burger Meal", price: 12.00, sortOrder: 0)
        f1.category = food
        
        event.products = [p1, p2, p3, p4, p5, p6, p7, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, m1, f1]
        
        // Enable multiple categories mode
        event.areCategoriesEnabled = false
        
        return event
    }()
    
    PanelView(event: sampleEvent, onQuit: nil)
        .modelContainer(for: [Event.self, Transaction.self])
        .environment(AuthService())
}
