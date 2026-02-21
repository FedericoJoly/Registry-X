import Foundation
import SwiftData

// MARK: - User
@Model
final class User: Identifiable {
    var id: UUID
    var username: String
    var email: String
    var fullName: String
    var passwordHash: String // In production, use Keychain or secure storage. simpler for now.
    var role: UserRole
    var createdAt: Date
    
    init(id: UUID = UUID(), username: String, email: String = "", fullName: String = "", passwordHash: String, role: UserRole = .staff, createdAt: Date = Date()) {
        self.id = id
        self.username = username
        self.email = email
        self.fullName = fullName
        self.passwordHash = passwordHash
        self.role = role
        self.createdAt = createdAt
    }
}

enum UserRole: String, Codable {
    case admin
    case staff
}

// MARK: - Event
@Model
final class Event {
    var id: UUID
    var name: String
    var date: Date
    var isLocked: Bool
    var isFinalised: Bool = false
    var pinCode: String?
    var closingDate: Date?
    
    var isStockControlEnabled: Bool = false
    
    // Relationships
    @Relationship(deleteRule: .cascade) var products: [Product] = []
    @Relationship(deleteRule: .cascade) var categories: [Category] = []
    @Relationship(deleteRule: .cascade) var transactions: [Transaction] = []
    @Relationship(deleteRule: .cascade) var rates: [EventExchangeRate] = [] // OLD - for migration
    @Relationship(deleteRule: .cascade) var currencies: [Currency] = [] // NEW
    @Relationship(deleteRule: .cascade) var promos: [Promo] = []
    
    // Event specific settings could be flattened here or separate
    var currencyCode: String
    var isTotalRoundUp: Bool = true
    var areCategoriesEnabled: Bool = true
    var arePromosEnabled: Bool = true
    var defaultProductBackgroundColor: String = "#FFFFFF" // White default
    var creatorName: String // Snapshot of creator's name
    var creatorId: UUID? // Link to User ID (Optional for backward compatibility/migration)
    var ratesLastUpdated: Date?
    var lastModified: Date = Date()
    var paymentMethodsData: Data? // Stores PaymentMethodOption array as JSON
    var mergedEventsData: Data? // Stores array of merged event identifiers (name + exportDate)
    
    // Stripe Integration Configuration
    var stripeIntegrationEnabled: Bool = false
    var stripePublishableKey: String?
    var stripeBackendURL: String?
    var stripeCompanyName: String?
    var stripeLocationId: String? // Terminal Location ID for Tap to Pay
    
    // Bizum Integration Configuration
    var bizumPhoneNumber: String?
    
    // Company Configuration (shared across integrations)
    var companyName: String?
    var fromName: String?  // Display name for outgoing emails
    var fromEmail: String? // Email address for outgoing emails
    
    // Receipt Configuration (per payment method)
    var receiptSettingsData: Data? // Stores [String: Bool] mapping (method name -> enabled)
    
    init(id: UUID = UUID(), name: String, date: Date, isLocked: Bool = false, isFinalised: Bool = false, pinCode: String? = nil, currencyCode: String = "USD", isTotalRoundUp: Bool = true, areCategoriesEnabled: Bool = true, arePromosEnabled: Bool = true, defaultProductBackgroundColor: String = "#FFFFFF", creatorName: String = "Unknown", creatorId: UUID? = nil, ratesLastUpdated: Date? = nil, lastModified: Date = Date(), stripeBackendURL: String? = nil, stripePublishableKey: String? = nil, stripeCompanyName: String? = nil, stripeLocationId: String? = nil, bizumPhoneNumber: String? = nil, receiptSettingsData: Data? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.isLocked = isLocked
        self.isFinalised = isFinalised
        self.pinCode = pinCode
        self.currencyCode = currencyCode
        self.isTotalRoundUp = isTotalRoundUp
        self.areCategoriesEnabled = areCategoriesEnabled
        self.arePromosEnabled = arePromosEnabled
        self.defaultProductBackgroundColor = defaultProductBackgroundColor
        self.creatorName = creatorName
        self.creatorId = creatorId
        self.ratesLastUpdated = ratesLastUpdated
        self.lastModified = lastModified
        self.stripeBackendURL = stripeBackendURL
        self.stripePublishableKey = stripePublishableKey
        self.stripeCompanyName = stripeCompanyName
        self.stripeLocationId = stripeLocationId
        self.bizumPhoneNumber = bizumPhoneNumber
        self.companyName = companyName
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.receiptSettingsData = receiptSettingsData
    }
    
    // Helper to generate PIN from current date (YYMMDD format)
    func generateDatePIN() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: Date()) // Use current date when finalising
    }
}

// MARK: - Product
@Model
final class Product {
    var id: UUID
    var name: String
    var price: Decimal
    var subgroup: String? // "Large", "Small", etc.
    var isActive: Bool = true
    var isPromo: Bool = false
    var sortOrder: Int = 0
    var isDeleted: Bool = false // Soft delete
    var stockQty: Int? = nil    // nil = not tracked; 0+ = tracked quantity
    
    @Relationship var category: Category?
    @Relationship(inverse: \Event.products) var event: Event?
    
    init(id: UUID = UUID(), name: String, price: Decimal, category: Category? = nil, subgroup: String? = nil, isActive: Bool = true, isPromo: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.price = price
        self.category = category
        self.subgroup = subgroup
        self.isActive = isActive
        self.isPromo = isPromo
        self.sortOrder = sortOrder
    }
}

// MARK: - Category
@Model
final class Category {
    var id: UUID
    var name: String
    var hexColor: String
    var isEnabled: Bool
    var sortOrder: Int
    
    @Relationship(inverse: \Event.categories) var event: Event?
    
    init(id: UUID = UUID(), name: String, hexColor: String = "#FF0000", isEnabled: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.hexColor = hexColor
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }
}

// MARK: - Split Entry (N-way split payment)
/// One leg of a split transaction. Stored as JSON in `Transaction.splitEntriesJSON`.
struct SplitEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var method: String           // PaymentMethod.rawValue or display name
    var methodIcon: String       // SF Symbol name
    var colorHex: String         // background color hex for the method icon
    var amountInMain: Decimal    // share in the event main currency
    var chargeAmount: Decimal    // amount in chargeCode (the currency the customer pays in)
    var currencyCode: String     // the charge currency code
    var cardLast4: String?       // last 4 digits of card, if paid by card (set from Stripe Terminal)
}

// MARK: - Transaction
@Model
final class Transaction {
    var id: UUID
    var timestamp: Date
    var totalAmount: Decimal
    var currencyCode: String // Added
    var note: String? // Added
    var paymentMethod: PaymentMethod
    var paymentMethodIcon: String? // Store actual icon (e.g. "phone.fill" for Bizum)
    
    // Transaction Reference (readable ID like "52D4A")
    var transactionRef: String?
    
    // Stripe Payment Integration
    var stripePaymentIntentId: String?
    var stripeSessionId: String?
    var paymentStatus: String? // "succeeded", "pending", "failed", "manual"
    
    // Receipt Email (for tap-to-pay receipts)
    var receiptEmail: String?
    // Last 4 digits of the card used (for card/TTP single payments; nil for non-card methods)
    var cardLast4: String?
    
    // Legacy 2-slot split fields — kept ONLY for SwiftData schema safety (do not read/write).
    // All split data lives in splitEntriesJSON / splitEntries.
    var isSplit: Bool = false
    var splitMethod: String?
    var splitMethodIcon: String?
    var splitAmount1: Decimal?
    var splitAmount2: Decimal?
    var splitCurrencyCode1: String?
    var splitCurrencyCode2: String?

    // N-way split: JSON-encoded [SplitEntry] (nil = not a split transaction)
    var splitEntriesJSON: String?

    /// Decoded split entries. Empty array = not a split transaction.
    var splitEntries: [SplitEntry] {
        get {
            guard let json = splitEntriesJSON,
                  let data = json.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([SplitEntry].self, from: data)
            else { return [] }
            return entries
        }
        set {
            if newValue.isEmpty {
                splitEntriesJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let str = String(data: data, encoding: .utf8) {
                splitEntriesJSON = str
            }
        }
    }

    /// True when this transaction was paid via multiple methods.
    var isNWaySplit: Bool { splitEntries.count >= 2 }

    // Simplification: We store a snapshot of items logic or relationship?
    // For a POS, usually better to store line items to track what was sold.
    @Relationship(deleteRule: .cascade) var lineItems: [LineItem] = []

    @Relationship(inverse: \Event.transactions) var event: Event?

    init(id: UUID = UUID(), timestamp: Date = Date(), totalAmount: Decimal, currencyCode: String, note: String? = nil, paymentMethod: PaymentMethod, paymentMethodIcon: String? = nil, transactionRef: String? = nil, stripePaymentIntentId: String? = nil, stripeSessionId: String? = nil, paymentStatus: String? = nil, receiptEmail: String? = nil, splitEntries: [SplitEntry] = [],
         // Legacy parameters for backward compatibility — not written to new fields
         isSplit: Bool = false, splitMethod: String? = nil, splitMethodIcon: String? = nil, splitAmount1: Decimal? = nil, splitAmount2: Decimal? = nil, splitCurrencyCode1: String? = nil, splitCurrencyCode2: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.note = note
        self.paymentMethod = paymentMethod
        self.paymentMethodIcon = paymentMethodIcon
        self.transactionRef = transactionRef
        self.stripePaymentIntentId = stripePaymentIntentId
        self.stripeSessionId = stripeSessionId
        self.paymentStatus = paymentStatus
        self.receiptEmail = receiptEmail
        // New N-way split
        if !splitEntries.isEmpty {
            if let data = try? JSONEncoder().encode(splitEntries),
               let str = String(data: data, encoding: .utf8) {
                self.splitEntriesJSON = str
            }
        } else if isSplit, let m2 = splitMethod, let a1 = splitAmount1, let a2 = splitAmount2,
                  let c1 = splitCurrencyCode1, let c2 = splitCurrencyCode2 {
            // Migrate legacy 2-slot call into new format
            let icon1 = paymentMethodIcon ?? "creditcard"
            let e1 = SplitEntry(method: paymentMethod.rawValue, methodIcon: icon1, colorHex: "", amountInMain: a1, chargeAmount: a1, currencyCode: c1)
            let e2 = SplitEntry(method: m2, methodIcon: splitMethodIcon ?? "banknote", colorHex: "", amountInMain: a2, chargeAmount: a2, currencyCode: c2)
            if let data = try? JSONEncoder().encode([e1, e2]),
               let str = String(data: data, encoding: .utf8) {
                self.splitEntriesJSON = str
            }
        }
        // Deprecated fields kept nil — no longer written
        self.isSplit = false
        self.splitMethod = nil
        self.splitMethodIcon = nil
        self.splitAmount1 = nil
        self.splitAmount2 = nil
        self.splitCurrencyCode1 = nil
        self.splitCurrencyCode2 = nil
    }
}

@Model
final class LineItem {
    var id: UUID
    var productName: String // Snapshot name in case product changes
    var quantity: Int
    var unitPrice: Decimal
    var subtotal: Decimal
    var subgroup: String? // Added
    
    @Relationship var product: Product? // Optional link back
    
    init(id: UUID = UUID(), productName: String, quantity: Int, unitPrice: Decimal, subgroup: String? = nil) {
        self.id = id
        self.productName = productName
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.subtotal = unitPrice * Decimal(quantity)
        self.subgroup = subgroup
    }
}

enum PaymentMethod: String, Codable, CaseIterable {
    case cash
    case card
    case transfer
    case other
}

// MARK: - Exchange Rate
// MARK: - Exchange Rate (Global Cache)
@Model
final class ExchangeRate {
    @Attribute(.unique) var currencyPair: String // e.g. "USD/EUR"
    var rate: Decimal
    var lastUpdated: Date
    
    init(currencyPair: String, rate: Decimal, lastUpdated: Date = Date()) {
        self.currencyPair = currencyPair
        self.rate = rate
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Event Exchange Rate (Scoped)
@Model
final class EventExchangeRate {
    var currencyCode: String // The target currency (e.g. "EUR")
    var rate: Decimal        // Value relative to Event's Main Currency
    var isManualOverride: Bool
    
    @Relationship(inverse: \Event.rates) var event: Event?
    
    init(currencyCode: String, rate: Decimal, isManualOverride: Bool = false) {
        self.currencyCode = currencyCode
        self.rate = rate
        self.isManualOverride = isManualOverride
    }
}

// MARK: - Currency (New Unified Model)
@Model
final class Currency {
    var id: UUID
    var code: String          // USD, EUR, GBP
    var symbol: String        // $, €, £
    var name: String          // US Dollar, Euro, British Pound
    var rate: Decimal         // Exchange rate (main currency is always 1.0)
    var isMain: Bool          // Only one per event
    var isEnabled: Bool       // Show in Panel currency buttons
    var isDefault: Bool       // USD/EUR/GBP can't be deleted
    var isManual: Bool        // User manually set rate
    var sortOrder: Int
    
    @Relationship(inverse: \Event.currencies) var event: Event?
    
    init(id: UUID = UUID(), code: String, symbol: String, name: String, rate: Decimal = 1.0, isMain: Bool = false, isEnabled: Bool = true, isDefault: Bool = false, isManual: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.code = code
        self.symbol = symbol
        self.name = name
        self.rate = rate
        self.isMain = isMain
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.isManual = isManual
        self.sortOrder = sortOrder
    }
}
// MARK: - Promo
@Model
final class Promo {
    var id: UUID
    var name: String
    var mode: PromoMode
    var sortOrder: Int
    var isActive: Bool
    var isDeleted: Bool
    
    // Type List specific properties
    var category: Category?
    var maxQuantity: Int
    
    // Pricing tiers: stored as Data, accessed as [Int: Decimal]
    var tierPricesData: Data?
    
    // Incremental pricing after max quantity
    var incrementalPrice8to9: Decimal?
    var incrementalPrice10Plus: Decimal?
    
    // Star products: stored as Data, accessed as [UUID: Decimal]
    var starProductsData: Data?
    
    // Combo mode properties
    var comboProductIds: Data?
    var comboPrice: Decimal?
    
    // N x M mode properties
    var nxmN: Int?
    var nxmM: Int?
    var nxmProductIds: Data?
    
    // Discount mode properties
    var discountValue: Decimal?
    var discountType: String?   // "numeric" or "percentage"
    var discountTarget: String? // "total" or "products"
    var discountProductIds: Data? // JSON Set<UUID>
    
    var event: Event?
    
    init(id: UUID = UUID(), name: String, mode: PromoMode = .typeList, sortOrder: Int = 0, isActive: Bool = true, isDeleted: Bool = false, category: Category? = nil, maxQuantity: Int = 7, incrementalPrice8to9: Decimal? = nil, incrementalPrice10Plus: Decimal? = nil) {
        self.id = id
        self.name = name
        self.mode = mode
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.isDeleted = isDeleted
        self.category = category
        self.maxQuantity = maxQuantity
        self.incrementalPrice8to9 = incrementalPrice8to9
        self.incrementalPrice10Plus = incrementalPrice10Plus
    }
    
    // Helper to get/set tier prices
    var tierPrices: [Int: Decimal] {
        get {
            guard let data = tierPricesData else { return [:] }
            return (try? JSONDecoder().decode([Int: Decimal].self, from: data)) ?? [:]
        }
        set {
            tierPricesData = try? JSONEncoder().encode(newValue)
        }
    }
    
    // Helper to get/set star products
    var starProducts: [UUID: Decimal] {
        get {
            guard let data = starProductsData else { return [:] }
            return (try? JSONDecoder().decode([UUID: Decimal].self, from: data)) ?? [:]
        }
        set {
            starProductsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    // Helper to get/set combo products
    var comboProducts: Set<UUID> {
        get {
            guard let data = comboProductIds else { return [] }
            return (try? JSONDecoder().decode(Set<UUID>.self, from: data)) ?? []
        }
        set {
            comboProductIds = try? JSONEncoder().encode(newValue)
        }
    }
    
    // Helper to get/set N x M products
    var nxmProducts: Set<UUID> {
        get {
            guard let data = nxmProductIds else { return [] }
            return (try? JSONDecoder().decode(Set<UUID>.self, from: data)) ?? []
        }
        set {
            nxmProductIds = try? JSONEncoder().encode(newValue)
        }
    }
}

enum PromoMode: String, Codable {
    case typeList
    case combo
    case nxm
    case discount
}

enum DiscountType: String, Codable, CaseIterable {
    case numeric
    case percentage
}

enum DiscountTarget: String, Codable, CaseIterable {
    case total
    case products
}
