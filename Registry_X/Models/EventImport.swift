import Foundation
import SwiftData
import SwiftUI

// MARK: - Event Import

extension EventExport {
    func createEvent(modelContext: ModelContext, userId: UUID?, username: String?) -> Event? {
        // Check for duplicate names and resolve conflicts
        var eventName = name
        var counter = 1
        
        // Fetch all existing events
        let descriptor = FetchDescriptor<Event>()
        let existingEvents = (try? modelContext.fetch(descriptor)) ?? []
        // Filter to only this user's events for uniqueness check
        let userEvents = existingEvents.filter { $0.creatorId == userId }
        
        // Keep incrementing counter until we find a unique name
        while userEvents.contains(where: { $0.name == eventName }) {
            eventName = "\(name) (\(counter))"
            counter += 1
        }
        
        // Create event with unique name
        let event = Event(
            name: eventName,
            date: date,
            isLocked: false,
            pinCode: nil,
            currencyCode: currencyCode,
            isTotalRoundUp: isTotalRoundUp,
            areCategoriesEnabled: areCategoriesEnabled,
            arePromosEnabled: arePromosEnabled,
            defaultProductBackgroundColor: defaultProductBackgroundColor,
            creatorName: username ?? creatorName,
            creatorId: userId,
            ratesLastUpdated: ratesLastUpdated,
            stripeBackendURL: stripeBackendURL,
            stripePublishableKey: stripePublishableKey,
            stripeCompanyName: stripeCompanyName,
            stripeLocationId: stripeLocationId,
            bizumPhoneNumber: bizumPhoneNumber,
            receiptSettingsData: receiptSettingsData
        )
        
        // Set company email configuration
        event.companyName = companyName
        event.fromName = fromName
        event.fromEmail = fromEmail
        
        // Set Stripe integration enabled flag (not in init)

        event.stripeIntegrationEnabled = stripeIntegrationEnabled ?? false
        
        modelContext.insert(event)
        
        // Import currencies and build ID map
        var currencyCodeToIdMap: [String: UUID] = [:]
        for (_, currExport) in currencies.enumerated() {
            let newCurrency = Currency(
                code: currExport.code,
                symbol: currExport.symbol,
                name: currExport.name,
                rate: currExport.rate,
                isMain: currExport.isMain,
                isEnabled: currExport.isEnabled,
                isDefault: currExport.isDefault,
                isManual: currExport.isManual,
                sortOrder: currExport.sortOrder
            )
            
            // Store old ID if we had one (for payment method mapping)
            // Map currency code to new currency ID
            currencyCodeToIdMap[currExport.code] = newCurrency.id
            
            newCurrency.event = event
            modelContext.insert(newCurrency)
        }
        
        // Import categories
        var categoryMap: [UUID: Category] = [:]
        for catExport in categories {
            let newCat = Category(
                id: catExport.id, // Preserve original ID
                name: catExport.name,
                hexColor: catExport.hexColor,
                isEnabled: catExport.isEnabled,
                sortOrder: catExport.sortOrder
            )
            newCat.event = event
            modelContext.insert(newCat)
            categoryMap[catExport.id] = newCat
        }
        
        // Import products
        var productMap: [UUID: Product] = [:]
        for prodExport in products {
            let linkedCategory = prodExport.categoryId != nil ? categoryMap[prodExport.categoryId!] : nil
            
            let newProd = Product(
                id: prodExport.id, // Preserve original ID
                name: prodExport.name,
                price: prodExport.price,
                category: linkedCategory,
                subgroup: prodExport.subgroup,
                isActive: prodExport.isActive,
                isPromo: prodExport.isPromo,
                sortOrder: prodExport.sortOrder
            )
            newProd.event = event
            modelContext.insert(newProd)
            productMap[prodExport.id] = newProd
        }
        
        // Import promos
        for promoExport in promos {
            var promoMode: PromoMode
            switch promoExport.mode {
            case "combo":
                promoMode = .combo
            case "nxm":
                promoMode = .nxm
            default:
                promoMode = .typeList
            }
            let linkedCategory = promoExport.categoryId != nil ? categoryMap[promoExport.categoryId!] : nil
            
            let newPromo = Promo(
                name: promoExport.name,
                mode: promoMode,
                sortOrder: promoExport.sortOrder,
                isActive: promoExport.isActive,
                isDeleted: false,
                category: linkedCategory,
                maxQuantity: promoExport.maxQuantity,
                incrementalPrice8to9: promoExport.incrementalPrice8to9,
                incrementalPrice10Plus: promoExport.incrementalPrice10Plus
            )
            
            // Set tier prices
            newPromo.tierPrices = promoExport.tierPrices
            
            // Set star products
            newPromo.starProducts = promoExport.starProducts
            
            // Set combo products
            newPromo.comboProducts = Set(promoExport.comboProductIds)
            newPromo.comboPrice = promoExport.comboPrice
            
            // Set N x M properties
            newPromo.nxmN = promoExport.nxmN
            newPromo.nxmM = promoExport.nxmM
            newPromo.nxmProducts = Set(promoExport.nxmProductIds)
            
            newPromo.event = event
            modelContext.insert(newPromo)
        }
        
        // Import payment methods
        // Build currency ID map using currency codes for stable mapping
        var importedPaymentMethods: [PaymentMethodOption] = []
        for methodExport in self.paymentMethods {

            // Map currency codes to actual currency IDs
            var enabledCurrencies: Set<UUID> = []
            for currCode in methodExport.enabledCurrencyCodes {
                // Find matching currency by code
                // 
                if let currId = currencyCodeToIdMap[currCode] { // Simplified - could be improved
                    enabledCurrencies.insert(currId)
                }

            }
            
            let newMethod = PaymentMethodOption(
                id: methodExport.id,
                name: methodExport.name,
                icon: methodExport.icon,
                colorHex: methodExport.colorHex,
                isEnabled: methodExport.isEnabled,
                enabledCurrencies: enabledCurrencies,
                enabledProviders: Set(methodExport.enabledProviders)
            )
            importedPaymentMethods.append(newMethod)
        }
        
        if !importedPaymentMethods.isEmpty {
            event.paymentMethodsData = try? JSONEncoder().encode(importedPaymentMethods)
        }
        
        // Import transactions
        for transExport in transactions {
            let paymentMethod = PaymentMethod(rawValue: transExport.paymentMethod) ?? .cash
            
            let newTrans = Transaction(
                timestamp: transExport.timestamp,
                totalAmount: transExport.totalAmount,
                currencyCode: transExport.currencyCode,
                note: transExport.note,
                paymentMethod: paymentMethod
            )
            newTrans.event = event
            modelContext.insert(newTrans)
            
            for itemExport in transExport.lineItems {
                let newItem = LineItem(
                    productName: itemExport.productName,
                    quantity: itemExport.quantity,
                    unitPrice: itemExport.unitPrice,
                    subgroup: itemExport.subgroup
                )
                
                // Try to link to product by name
                if let product = event.products.first(where: { $0.name == itemExport.productName }) {
                    newItem.product = product
                }
                
                newTrans.lineItems.append(newItem)
                modelContext.insert(newItem)
            }
        }
        
        return event
    }
    
    // MARK: - Merge Into Existing Event
    
    func mergeIntoEvent(event: Event, modelContext: ModelContext) throws {
        // Merge boolean settings (additive - if either is ON, result is ON)
        event.areCategoriesEnabled = event.areCategoriesEnabled || areCategoriesEnabled
        event.arePromosEnabled = event.arePromosEnabled || arePromosEnabled
        event.isTotalRoundUp = event.isTotalRoundUp || isTotalRoundUp
        
        // Merge currencies (add new ones, update existing by code)
        var currencyCodeToIdMap: [String: UUID] = [:]
        for currExport in currencies {
            if let existing = event.currencies.first(where: { $0.code == currExport.code }) {
                // Currency exists - keep existing (don't overwrite)
                currencyCodeToIdMap[currExport.code] = existing.id
            } else {
                // New currency - add it
                let newCurrency = Currency(
                    code: currExport.code,
                    symbol: currExport.symbol,
                    name: currExport.name,
                    rate: currExport.rate,
                    isMain: currExport.isMain,
                    isEnabled: currExport.isEnabled,
                    isDefault: currExport.isDefault,
                    isManual: currExport.isManual,
                    sortOrder: event.currencies.count
                )
                newCurrency.event = event
                modelContext.insert(newCurrency)
                currencyCodeToIdMap[currExport.code] = newCurrency.id
            }
        }
        
        // Merge categories (add new ones by name)
        var categoryIdMap: [UUID: UUID] = [:]
        for catExport in categories {
            if let existing = event.categories.first(where: { $0.name == catExport.name }) {
                // Category exists - keep existing
                categoryIdMap[catExport.id] = existing.id
            } else {
                // New category - add it
                let newCategory = Category(
                    name: catExport.name,
                    hexColor: catExport.hexColor,
                    sortOrder: event.categories.count
                )
                newCategory.event = event
                modelContext.insert(newCategory)
                categoryIdMap[catExport.id] = newCategory.id
            }
        }
        
        // Merge products (add new ones by name)
        var productIdMap: [UUID: UUID] = [:]
        for prodExport in products {
            if let existing = event.products.first(where: { $0.name == prodExport.name }) {
                // Product exists - keep existing
                productIdMap[prodExport.id] = existing.id
            } else {
                // New product - add it
                let newProduct = Product(
                    name: prodExport.name,
                    price: prodExport.price,
                    isActive: prodExport.isActive,
                    isPromo: prodExport.isPromo,
                    sortOrder: event.products.count
                )
                newProduct.event = event
                newProduct.subgroup = prodExport.subgroup
                
                // Link to category if available
                if let oldCatId = prodExport.categoryId, let newCatId = categoryIdMap[oldCatId] {
                    newProduct.category = event.categories.first(where: { $0.id == newCatId })
                }
                
                modelContext.insert(newProduct)
                productIdMap[prodExport.id] = newProduct.id
            }
        }
        
        // Merge promos (add new ones by name)
        for promoExport in promos {
            if event.promos.contains(where: { $0.name == promoExport.name }) {
                // Promo exists - skip
                continue
            }
            
            // New promo - add it
            let newPromo = Promo(
                name: promoExport.name,
                mode: PromoMode(rawValue: promoExport.mode) ?? .typeList,
                sortOrder: event.promos.count,
                isActive: promoExport.isActive,
                maxQuantity: promoExport.maxQuantity
            )
            newPromo.event = event
            
            // Link category
            if let oldCatId = promoExport.categoryId, let newCatId = categoryIdMap[oldCatId] {
                newPromo.category = event.categories.first(where: { $0.id == newCatId })
            }
            
            // Set tier prices
            newPromo.tierPrices = promoExport.tierPrices
            newPromo.incrementalPrice8to9 = promoExport.incrementalPrice8to9
            newPromo.incrementalPrice10Plus = promoExport.incrementalPrice10Plus
            
            // Map star products
            var newStarProducts: [UUID: Decimal] = [:]
            for (oldProdId, cost) in promoExport.starProducts {
                if let newProdId = productIdMap[oldProdId] {
                    newStarProducts[newProdId] = cost
                }
            }
            newPromo.starProducts = newStarProducts
            
            // Map combo products
            var newComboProducts: Set<UUID> = []
            for oldProdId in promoExport.comboProductIds {
                if let newProdId = productIdMap[oldProdId] {
                    newComboProducts.insert(newProdId)
                }
            }
            newPromo.comboProducts = newComboProducts
            newPromo.comboPrice = promoExport.comboPrice
            
            // Map N x M products
            var newNxMProducts: Set<UUID> = []
            for oldProdId in promoExport.nxmProductIds {
                if let newProdId = productIdMap[oldProdId] {
                    newNxMProducts.insert(newProdId)
                }
            }
            newPromo.nxmProducts = newNxMProducts
            newPromo.nxmN = promoExport.nxmN
            newPromo.nxmM = promoExport.nxmM
            
            modelContext.insert(newPromo)
        }
        
        // Merge payment methods (add new ones by name)
        var existingPaymentMethods: [PaymentMethodOption] = []
        if let data = event.paymentMethodsData,
           let decoded = try? JSONDecoder().decode([PaymentMethodOption].self, from: data) {
            existingPaymentMethods = decoded
        }
        
        for methodExport in paymentMethods {
            if existingPaymentMethods.contains(where: { $0.name == methodExport.name }) {
                // Payment method exists - skip
                continue
            }
            
            // New payment method - add it
            var enabledCurrencies: Set<UUID> = []
            for code in methodExport.enabledCurrencyCodes {
                if let currencyId = currencyCodeToIdMap[code] {
                    enabledCurrencies.insert(currencyId)
                }
            }
            
            let newMethod = PaymentMethodOption(
                id: UUID(),
                name: methodExport.name,
                icon: methodExport.icon,
                colorHex: methodExport.colorHex,
                isEnabled: methodExport.isEnabled,
                enabledCurrencies: enabledCurrencies,
                enabledProviders: Set(methodExport.enabledProviders)
            )
            existingPaymentMethods.append(newMethod)
        }
        
        // Save updated payment methods
        if !existingPaymentMethods.isEmpty {
            event.paymentMethodsData = try? JSONEncoder().encode(existingPaymentMethods)
        }
        
        // Merge receipt settings (keep existing if present, otherwise use imported)
        if event.receiptSettingsData == nil && receiptSettingsData != nil {
            event.receiptSettingsData = receiptSettingsData
        }
        
        // Append all transactions (no deduplication)
        for transExport in transactions {
            let paymentMethod = PaymentMethod(rawValue: transExport.paymentMethod) ?? .cash
            
            let newTrans = Transaction(
                timestamp: transExport.timestamp,
                totalAmount: transExport.totalAmount,
                currencyCode: transExport.currencyCode,
                note: transExport.note,
                paymentMethod: paymentMethod
            )
            newTrans.event = event
            modelContext.insert(newTrans)
            
            for itemExport in transExport.lineItems {
                let newItem = LineItem(
                    productName: itemExport.productName,
                    quantity: itemExport.quantity,
                    unitPrice: itemExport.unitPrice,
                    subgroup: itemExport.subgroup
                )
                
                // Try to link to product by name
                if let product = event.products.first(where: { $0.name == itemExport.productName }) {
                    newItem.product = product
                }
                
                newTrans.lineItems.append(newItem)
                modelContext.insert(newItem)
            }
        }
    }
}
