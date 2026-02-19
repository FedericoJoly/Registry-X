import Foundation
import SwiftData

// MARK: - Event Export/Import Models

struct EventExport: Codable, Sendable {
    // Event identifier (optional for backward compatibility)
    let eventId: UUID?
    
    // Basic info
    let name: String
    let date: Date
    let currencyCode: String
    let isTotalRoundUp: Bool
    let areCategoriesEnabled: Bool
    let arePromosEnabled: Bool
    let defaultProductBackgroundColor: String
    let creatorName: String
    let ratesLastUpdated: Date?
    
    // Stripe Configuration
    let stripeIntegrationEnabled: Bool?
    let stripeBackendURL: String?
    let stripePublishableKey: String?
    let stripeCompanyName: String?
    let stripeLocationId: String?
    
    // Bizum Configuration
    let bizumPhoneNumber: String?
    
    // Company Email Configuration
    let companyName: String?
    let fromName: String?
    let fromEmail: String?
    
    // Receipt Configuration
    let receiptSettingsData: Data?
    
    // Closing Date
    let closingDate: Date?
    
    // Stock Control
    let isStockControlEnabled: Bool?
    
    // Data
    let currencies: [CurrencyExport]
    let categories: [CategoryExport]
    let products: [ProductExport]
    let promos: [PromoExport]
    let paymentMethods: [PaymentMethodExport]
    let transactions: [TransactionExport]
    
    // Version for future compatibility
    var exportVersion: String = "1.0"
    var exportDate: Date = Date()
}

struct CurrencyExport: Codable, Sendable {
    let code: String
    let symbol: String
    let name: String
    let rate: Decimal
    let isMain: Bool
    let isEnabled: Bool
    let isDefault: Bool
    let isManual: Bool
    let sortOrder: Int
}

struct CategoryExport: Codable, Sendable {
    let id: UUID
    let name: String
    let hexColor: String
    let isEnabled: Bool
    let sortOrder: Int
}

struct ProductExport: Codable, Sendable {
    let id: UUID
    let name: String
    let price: Decimal
    let categoryId: UUID?
    let subgroup: String?
    let isActive: Bool
    let isPromo: Bool
    let sortOrder: Int
    let stockQty: Int?  // nil = not tracked
}

struct PromoExport: Codable, Sendable {
    let name: String
    let mode: String
    let sortOrder: Int
    let isActive: Bool
    let categoryId: UUID?
    let maxQuantity: Int
    let tierPrices: [Int: Decimal]
    let incrementalPrice8to9: Decimal?
    let incrementalPrice10Plus: Decimal?
    let starProducts: [UUID: Decimal]
    let comboProductIds: [UUID]
    let comboPrice: Decimal?
    let nxmN: Int?
    let nxmM: Int?
    let nxmProductIds: [UUID]
    // Discount mode
    let discountValue: Decimal?
    let discountType: String?
    let discountTarget: String?
    let discountProductIds: [UUID]
}

struct PaymentMethodExport: Codable, Sendable {
    let id: UUID
    let name: String
    let icon: String
    let colorHex: String
    let isEnabled: Bool
    let enabledCurrencyCodes: [String]
    let enabledProviders: [String]
}

struct TransactionExport: Codable, Sendable {
    let timestamp: Date
    let totalAmount: Decimal
    let currencyCode: String
    let note: String?
    let paymentMethod: String
    let lineItems: [LineItemExport]
}

struct LineItemExport: Codable {
    let productName: String
    let quantity: Int
    let unitPrice: Decimal
    let subgroup: String?
}

// MARK: - Export Extensions

@MainActor
extension Event {
    func exportToJSON() -> Data? {
        // Build currency list (map IDs to export)
        var currencyIdMap: [UUID: UUID] = [:]
        let currencyExports = currencies.enumerated().map { index, curr in
            let exportId = UUID()
            currencyIdMap[curr.id] = exportId
            return CurrencyExport(
                code: curr.code,
                symbol: curr.symbol,
                name: curr.name,
                rate: curr.rate,
                isMain: curr.isMain,
                isEnabled: curr.isEnabled,
                isDefault: curr.isDefault,
                isManual: curr.isManual,
                sortOrder: curr.sortOrder
            )
        }
        
        // Build category list
        let categoryExports = categories.map { cat in
            CategoryExport(
                id: cat.id,
                name: cat.name,
                hexColor: cat.hexColor,
                isEnabled: cat.isEnabled,
                sortOrder: cat.sortOrder
            )
        }
        
        // Build product list
        let productExports = products.map { prod in
            ProductExport(
                id: prod.id,
                name: prod.name,
                price: prod.price,
                categoryId: prod.category?.id,
                subgroup: prod.subgroup,
                isActive: prod.isActive,
                isPromo: prod.isPromo,
                sortOrder: prod.sortOrder,
                stockQty: prod.stockQty
            )
        }
        
        // Build promo list
        let promoExports = promos.map { promo in
            var modeString: String
            switch promo.mode {
            case .typeList:
                modeString = "typeList"
            case .combo:
                modeString = "combo"
            case .nxm:
                modeString = "nxm"
            case .discount:
                modeString = "discount"
            }
            
            let discountIds = (try? JSONDecoder().decode([UUID].self, from: promo.discountProductIds ?? Data())) ?? []
            
            return PromoExport(
                name: promo.name,
                mode: modeString,
                sortOrder: promo.sortOrder,
                isActive: promo.isActive,
                categoryId: promo.category?.id,
                maxQuantity: promo.maxQuantity,
                tierPrices: promo.tierPrices,
                incrementalPrice8to9: promo.incrementalPrice8to9,
                incrementalPrice10Plus: promo.incrementalPrice10Plus,
                starProducts: promo.starProducts,
                comboProductIds: Array(promo.comboProducts),
                comboPrice: promo.comboPrice,
                nxmN: promo.nxmN,
                nxmM: promo.nxmM,
                nxmProductIds: Array(promo.nxmProducts),
                discountValue: promo.discountValue,
                discountType: promo.discountType,
                discountTarget: promo.discountTarget,
                discountProductIds: discountIds
            )
        }
        
        // Build payment method list with currency codes
        var paymentExports: [PaymentMethodExport] = []
        if let paymentData = paymentMethodsData,
           let methods = try? JSONDecoder().decode([PaymentMethodOption].self, from: paymentData) {
            // Create lookup dictionary for O(1) currency ID -> code mapping
            let currencyLookup = Dictionary(uniqueKeysWithValues: currencies.map { ($0.id, $0.code) })
            
            paymentExports = methods.map { method in
                // Map currency IDs to codes using dictionary lookup (O(1) instead of O(n))
                let enabledCodes = method.enabledCurrencies.compactMap { currId in
                    currencyLookup[currId]
                }
                
                return PaymentMethodExport(
                    id: method.id,
                    name: method.name,
                    icon: method.icon,
                    colorHex: method.colorHex,
                    isEnabled: method.isEnabled,
                    enabledCurrencyCodes: enabledCodes,
                    enabledProviders: Array(method.enabledProviders)
                )
            }
        }
        
        // Build transaction list
        let transactionExports = transactions.map { trans in
            let lineItemExports = trans.lineItems.map { item in
                LineItemExport(
                    productName: item.productName,
                    quantity: item.quantity,
                    unitPrice: item.unitPrice,
                    subgroup: item.subgroup
                )
            }
            
            return TransactionExport(
                timestamp: trans.timestamp,
                totalAmount: trans.totalAmount,
                currencyCode: trans.currencyCode,
                note: trans.note,
                paymentMethod: trans.paymentMethod.rawValue,
                lineItems: lineItemExports
            )
        }
        
        // Create export object
        let export = EventExport(
            eventId: id,
            name: name,
            date: date,
            currencyCode: currencyCode,
            isTotalRoundUp: isTotalRoundUp,
            areCategoriesEnabled: areCategoriesEnabled,
            arePromosEnabled: arePromosEnabled,
            defaultProductBackgroundColor: defaultProductBackgroundColor,
            creatorName: creatorName,
            ratesLastUpdated: ratesLastUpdated,
            stripeIntegrationEnabled: stripeIntegrationEnabled,
            stripeBackendURL: stripeBackendURL,
            stripePublishableKey: stripePublishableKey,
            stripeCompanyName: stripeCompanyName,
            stripeLocationId: stripeLocationId,
            bizumPhoneNumber: bizumPhoneNumber,
            companyName: companyName,
            fromName: fromName,
            fromEmail: fromEmail,
            receiptSettingsData: receiptSettingsData,
            closingDate: closingDate,
            isStockControlEnabled: isStockControlEnabled,
            currencies: currencyExports,
            categories: categoryExports,
            products: productExports,
            promos: promoExports,
            paymentMethods: paymentExports,
            transactions: transactionExports
        )
        
        // Encode to JSON (no pretty printing for performance)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        return try? encoder.encode(export)
    }
}
