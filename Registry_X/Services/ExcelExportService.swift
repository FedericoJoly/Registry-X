import Foundation
import SwiftData

@MainActor
class ExcelExportService {
    
    static func generateExcelData(event: Event, username: String) -> Data? {
        do {
            return try createXLSXWithLibrary(event: event)
        } catch {
            print("Error creating XLSX: \(error)")
            return nil
        }
    }
    
    private static func createXLSXWithLibrary(event: Event) throws -> Data {
        let writer = SimpleXLSXWriter()
        
        // Get all products
        let allProducts = event.products.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        
        // Sheet 1: Registry (transactions)
        let registryIndex = writer.addWorksheet(name: "Registry", frozenRows: 1)
        
        // Header row
        var headers: [SimpleXLSXWriter.CellValue] = [
            .text("TX ID", bold: true, centered: true),
            .text("TX Date", bold: true, centered: true),
            .text("TX Time", bold: true, centered: true),
            .text("Payment Method", bold: true, centered: true),
            .text("Currency", bold: true, centered: true),
            .text("Total", bold: true, centered: true),
            .text("Discount", bold: true, centered: true),
            .text("Subtotal", bold: true, centered: true),
            .text("Note", bold: true, centered: true),
            .text("Email", bold: true, centered: true)
        ]
        for product in allProducts {
            headers.append(.text(product.name, bold: true))
        }
        writer.addRow(to: registryIndex, values: headers)
        
        // Data rows
        let transactions = event.transactions.sorted { $0.timestamp < $1.timestamp }
        for transaction in transactions {
            var row: [SimpleXLSXWriter.CellValue] = []
            
            // TX ID
            row.append(.text(transaction.transactionRef ?? transaction.id.uuidString.prefix(8).uppercased()))
            
            // TX Date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            row.append(.text(dateFormatter.string(from: transaction.timestamp)))
            
            // TX Time
            dateFormatter.dateFormat = "HH:mm:ss"
            row.append(.text(dateFormatter.string(from: transaction.timestamp)))
            
            // Payment Method
            row.append(.text(paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)))
            
            // Currency
            row.append(.text(transaction.currencyCode))
            
            // Total
            row.append(.decimal(transaction.totalAmount))
            
            // Discount (calculate from line items)
            let subtotal = transaction.lineItems.reduce(Decimal(0)) { $0 + $1.subtotal }
            let discount = subtotal - transaction.totalAmount
            row.append(.decimal(discount))
            
            // Subtotal
            row.append(.decimal(subtotal))
            
            // Note
            row.append(.text(transaction.note ?? ""))
            
            // Email
            row.append(.text(transaction.receiptEmail ?? ""))
            
            // Product quantities
            var productQuantities: [UUID: Int] = [:]
            for lineItem in transaction.lineItems {
                if let product = event.products.first(where: {
                    $0.name == lineItem.productName && $0.subgroup == lineItem.subgroup
                }) {
                    productQuantities[product.id, default: 0] += lineItem.quantity
                }
            }
            
            for product in allProducts {
                let qty = productQuantities[product.id] ?? 0
                row.append(.number(Double(qty)))
            }
            
            writer.addRow(to: registryIndex, values: row)
        }
        
        // Sheet 2: Currencies
        let currenciesIndex = writer.addWorksheet(name: "Currencies", frozenRows: 1)
        
        writer.addRow(to: currenciesIndex, values: [
            .text("Currency", bold: true, centered: true),
            .text("Payment Method", bold: true, centered: true),
            .text("Count", bold: true, centered: true),
            .text("Total", bold: true, centered: true),
            .empty  // Column E for currency totals
        ])
        
        // Collect stats by currency and method
        var currencyStats: [String: (currency: String, method: String, count: Int, total: Decimal)] = [:]
        var currencyTotals: [String: Decimal] = [:]
        
        for transaction in event.transactions {
            let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
            let key = "\(transaction.currencyCode)-\(methodName)"
            
            if currencyStats[key] == nil {
                currencyStats[key] = (transaction.currencyCode, methodName, 0, 0)
            }
            currencyStats[key]?.count += 1
            currencyStats[key]?.total += transaction.totalAmount
            
            currencyTotals[transaction.currencyCode, default: 0] += transaction.totalAmount
        }
        
        // Sort by currency, then alphabetically by payment method
        let paymentMethodOrder = ["Bizum", "Card", "Cash", "QR"]
        let sorted = currencyStats.sorted { first, second in
            if first.value.currency != second.value.currency {
                return first.value.currency < second.value.currency
            }
            let firstIndex = paymentMethodOrder.firstIndex(of: first.value.method) ?? 999
            let secondIndex = paymentMethodOrder.firstIndex(of: second.value.method) ?? 999
            return firstIndex < secondIndex
        }
        
        // Group by currency to add totals
        var currentCurrency = ""
        for (_, stats) in sorted {
            let isLastOfCurrency = sorted.last(where: { $0.value.currency == stats.currency })?.value.method == stats.method
            
            writer.addRow(to: currenciesIndex, values: [
                .text(stats.currency),
                .text(stats.method),
                .number(Double(stats.count)),
                .decimal(stats.total),
                isLastOfCurrency ? .decimal(currencyTotals[stats.currency] ?? 0) : .empty
            ])
            
            currentCurrency = stats.currency
        }
        
        // Add category subtotals section
        writer.addRow(to: currenciesIndex, values: [.empty, .empty, .empty, .empty, .empty])
        writer.addRow(to: currenciesIndex, values: [
            .text("Category Totals", bold: true, centered: true),
            .empty,
            .empty,
            .text("Subtotal", bold: true, centered: true),
            .empty
        ])
        
        // Calculate category totals using EXACT same logic as TotalsView.swift
        var categoryDict: [UUID: (category: Category, total: Decimal)] = [:]
        
        for transaction in event.transactions {
            for item in transaction.lineItems {
                if let category = item.product?.category {
                    // Convert to main currency with round-up (same as TotalsView)
                    let subtotalInMain = convertToMainCurrency(item.subtotal, from: transaction.currencyCode, event: event)
                    
                    if let existing = categoryDict[category.id] {
                        categoryDict[category.id] = (category, existing.total + subtotalInMain)
                    } else {
                        categoryDict[category.id] = (category, subtotalInMain)
                    }
                }
            }
        }
        
        // Sort by category sortOrder (same as TotalsView)
        let categoryTotals = categoryDict.map { $0.value }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
        
        var categoryGrandTotal: Decimal = 0
        for (category, total) in categoryTotals {
            writer.addRow(to: currenciesIndex, values: [
                .text(category.name),
                .empty,
                .empty,
                .decimal(total),
                .empty
            ])
            categoryGrandTotal += total
        }
        
        writer.addRow(to: currenciesIndex, values: [
            .text("Total", bold: true),
            .empty,
            .empty,
            .decimal(categoryGrandTotal),
            .empty
        ])

        
        // Sheet 3: Products Summary - using EXACT same logic as TotalsView.groupedByProduct
        let productsIndex = writer.addWorksheet(name: "Products", frozenRows: 1)
        
        writer.addRow(to: productsIndex, values: [
            .text("Product", bold: true, centered: true),
            .text("Units Sold", bold: true, centered: true),
            .text("Avg Price", bold: true, centered: true),
            .text("Total", bold: true, centered: true)
        ])
        
        // Group by product name (same as TotalsView)
        var productDict: [String: (category: Category?, items: [(item: LineItem, currencyCode: String)])] = [:]
        
        for transaction in event.transactions {
            for item in transaction.lineItems {
                if productDict[item.productName] == nil {
                    productDict[item.productName] = (item.product?.category, [])
                }
                productDict[item.productName]?.items.append((item, transaction.currencyCode))
            }
        }
        
        // Calculate totals with currency conversion (same as TotalsView)
        var productResults: [(name: String, category: Category?, units: Int, total: Decimal)] = []
        for (productName, value) in productDict {
            let (category, items) = value
            
            var totalInMainCurrency = Decimal(0)
            var totalUnits = 0
            
            for (item, currencyCode) in items {
                let subtotalInMain = convertToMainCurrency(item.subtotal, from: currencyCode, event: event)
                totalInMainCurrency += subtotalInMain
                totalUnits += item.quantity
            }
            
            productResults.append((productName, category, totalUnits, totalInMainCurrency))
        }
        
        // Sort by product sortOrder (same as TotalsView)
        let sortedProducts = productResults.sorted { prod1, prod2 in
            guard let p1 = event.products.first(where: { $0.name == prod1.name }),
                  let p2 = event.products.first(where: { $0.name == prod2.name }) else {
                return prod1.name < prod2.name
            }
            return p1.sortOrder < p2.sortOrder
        }
        
        var grandTotal: Decimal = 0
        for product in sortedProducts {
            let avgPrice = product.total / Decimal(product.units)
            writer.addRow(to: productsIndex, values: [
                .text(product.name),
                .number(Double(product.units)),
                .decimal(avgPrice),
                .decimal(product.total)
            ])
            grandTotal += product.total
        }
        
        writer.addRow(to: productsIndex, values: [
            .text("TOTAL", bold: true, centered: true),
            .empty,
            .empty,
            .decimal(grandTotal)
        ])
        
        // Sheet 4: Groups
        let groupsIndex = writer.addWorksheet(name: "Groups", frozenRows: 1)
        
        writer.addRow(to: groupsIndex, values: [
            .text("Group", bold: true, centered: true),
            .text("Units", bold: true, centered: true),
            .text("Total", bold: true, centered: true)
        ])
        
        var categoryStats: [UUID: (category: Category, units: Int, total: Decimal)] = [:]
        var subgroupStats: [String: (units: Int, total: Decimal)] = [:]
        
        for transaction in event.transactions {
            for lineItem in transaction.lineItems {
                if let product = event.products.first(where: {
                    $0.name == lineItem.productName && $0.subgroup == lineItem.subgroup
                }) {
                    if let category = product.category, !category.isDeleted {
                        if categoryStats[category.id] == nil {
                            categoryStats[category.id] = (category, 0, 0)
                        }
                        categoryStats[category.id]?.units += lineItem.quantity
                        categoryStats[category.id]?.total += lineItem.subtotal
                    }
                    
                    if let subgroup = product.subgroup {
                        if subgroupStats[subgroup] == nil {
                            subgroupStats[subgroup] = (0, 0)
                        }
                        subgroupStats[subgroup]?.units += lineItem.quantity
                        subgroupStats[subgroup]?.total += lineItem.subtotal
                    }
                }
            }
        }
        
        writer.addRow(to: groupsIndex, values: [.text("Categories", bold: true, centered: true), .empty, .empty])
        for (_, stats) in categoryStats.sorted(by: { $0.value.category.name < $1.value.category.name }) {
            writer.addRow(to: groupsIndex, values: [
                .text(stats.category.name),
                .number(Double(stats.units)),
                .decimal(stats.total)
            ])
        }
        
        writer.addRow(to: groupsIndex, values: [.empty, .empty, .empty])
        writer.addRow(to: groupsIndex, values: [.text("Subgroups", bold: true, centered: true), .empty, .empty])
        for (subgroup, stats) in subgroupStats.sorted(by: { $0.key < $1.key }) {
            writer.addRow(to: groupsIndex, values: [
                .text(subgroup),
                .number(Double(stats.units)),
                .decimal(stats.total)
            ])
        }
        
        return try writer.generateXLSX()
    }
    
    // MARK: - Utilities
    
    private static func paymentMethodName(_ method: PaymentMethod, icon: String? = nil) -> String {
        // Check for specific icons first
        if let icon = icon {
            if icon == "phone.fill" {
                return "Bizum"
            } else if icon == "qrcode" {
                return "QR"
            }
        }
        
        // Default method names
        switch method {
        case .cash:
            return "Cash"
        case .card:
            return "Card"
        case .transfer:
            return "QR"
        case .other:
            return "QR"  // Other payments are QR
        }
    }
    
    // MARK: - Currency Conversion (copied from TotalsView.swift)
    
    private static func convertToMainCurrency(_ amount: Decimal, from currencyCode: String, event: Event) -> Decimal {
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        let mainCode = mainCurrency?.code ?? event.currencyCode
        
        if currencyCode == mainCode { return amount }
        
        let rate = event.currencies.first(where: { $0.code == currencyCode })?.rate ?? 1.0
        let converted = amount / rate
        
        // Apply round-up if enabled (CRITICAL for matching app totals)
        if event.isTotalRoundUp {
            return Decimal(ceil(NSDecimalNumber(decimal: converted).doubleValue))
        }
        return converted
    }
}
