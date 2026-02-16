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
            .text("TX ID", bold: true),
            .text("TX Date", bold: true),
            .text("TX Time", bold: true),
            .text("Payment Method", bold: true),
            .text("Currency", bold: true),
            .text("Total", bold: true),
            .text("Discount", bold: true),
            .text("Subtotal", bold: true),
            .text("Note", bold: true),
            .text("Email", bold: true)
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
            .text("Currency", bold: true),
            .text("Payment Method", bold: true),
            .text("Count", bold: true),
            .text("Total", bold: true)
        ])
        
        var currencyStats: [String: (currency: String, method: String, count: Int, total: Decimal)] = [:]
        for transaction in event.transactions {
            let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
            let key = "\(transaction.currencyCode)-\(methodName)"
            
            if currencyStats[key] == nil {
                currencyStats[key] = (transaction.currencyCode, methodName, 0, 0)
            }
            currencyStats[key]?.count += 1
            currencyStats[key]?.total += transaction.totalAmount
        }
        
        for (_, stats) in currencyStats.sorted(by: { $0.value.currency < $1.value.currency }) {
            writer.addRow(to: currenciesIndex, values: [
                .text(stats.currency),
                .text(stats.method),
                .number(Double(stats.count)),
                .decimal(stats.total)
            ])
        }
        
        // Sheet 3: Products Summary
        let productsIndex = writer.addWorksheet(name: "Products", frozenRows: 1)
        
        writer.addRow(to: productsIndex, values: [
            .text("Product", bold: true),
            .text("Units Sold", bold: true),
            .text("Avg Price", bold: true),
            .text("Total", bold: true)
        ])
        
        var productStats: [UUID: (product: Product, units: Int, revenue: Decimal)] = [:]
        for transaction in event.transactions {
            for lineItem in transaction.lineItems {
                if let product = event.products.first(where: {
                    $0.name == lineItem.productName && $0.subgroup == lineItem.subgroup
                }), !product.isDeleted {
                    if productStats[product.id] == nil {
                        productStats[product.id] = (product, 0, 0)
                    }
                    productStats[product.id]?.units += lineItem.quantity
                    productStats[product.id]?.revenue += lineItem.subtotal
                }
            }
        }
        
        var grandTotal: Decimal = 0
        for product in allProducts {
            let categoryName = product.category?.name ?? "No Category"
            if let stats = productStats[product.id], stats.units > 0 {
                let avgPrice = stats.revenue / Decimal(stats.units)
                writer.addRow(to: productsIndex, values: [
                    .text(product.name),
                    .number(Double(stats.units)),
                    .decimal(avgPrice),
                    .decimal(stats.revenue)
                ])
                grandTotal += stats.revenue
            }
        }
        
        writer.addRow(to: productsIndex, values: [
            .text("TOTAL", bold: true),
            .empty,
            .empty,
            .decimal(grandTotal)
        ])
        
        // Sheet 4: Groups
        let groupsIndex = writer.addWorksheet(name: "Groups", frozenRows: 1)
        
        writer.addRow(to: groupsIndex, values: [
            .text("Group", bold: true),
            .text("Units", bold: true),
            .text("Total", bold: true)
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
        
        writer.addRow(to: groupsIndex, values: [.text("Categories", bold: true), .empty, .empty])
        for (_, stats) in categoryStats.sorted(by: { $0.value.category.name < $1.value.category.name }) {
            writer.addRow(to: groupsIndex, values: [
                .text(stats.category.name),
                .number(Double(stats.units)),
                .decimal(stats.total)
            ])
        }
        
        writer.addRow(to: groupsIndex, values: [.empty, .empty, .empty])
        writer.addRow(to: groupsIndex, values: [.text("Subgroups", bold: true), .empty, .empty])
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
            return "Other"
        }
    }
}
