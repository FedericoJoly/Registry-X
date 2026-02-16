import Foundation
import SwiftData
import ZIPFoundation

@MainActor
class ExcelExportService {
    
    /// Generates proper XLSX data with 3 separate sheets
    /// Returns Data that can be saved as .xlsx file (Office Open XML format)
    static func generateExcelData(event: Event, username: String) -> Data? {
        return createXLSXPackage(event: event)
    }
    
    // MARK: - XLSX Package Creation
    
    private static func createXLSXPackage(event: Event) -> Data? {
        // Create temporary directory for XLSX components
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xlsx")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Create XLSX structure
            try createXLSXStructure(in: tempDir, event: event)
            
            // Create ZIP archive using ZIPFoundation
            // Zip the contents of tempDir, not tempDir itself
            try FileManager.default.zipItem(at: tempDir, to: zipURL, shouldKeepParent: false, compressionMethod: .deflate)
            
            // Read the ZIP data
            let data = try Data(contentsOf: zipURL)
            
            // Clean up
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: zipURL)
            
            return data
            
        } catch {
            print("Error creating XLSX: \(error)")
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: zipURL)
            return nil
        }
    }
    
    private static func createXLSXStructure(in dir: URL, event: Event) throws {
        // Create directory structure
        let xlDir = dir.appendingPathComponent("xl")
        let relsDir = dir.appendingPathComponent("_rels")
        let xlRelsDir = xlDir.appendingPathComponent("_rels")
        let worksheetsDir = xlDir.appendingPathComponent("worksheets")
        
        try FileManager.default.createDirectory(at: xlDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worksheetsDir, withIntermediateDirectories: true)
        
        // [Content_Types].xml
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            <Override PartName="/xl/worksheets/sheet4.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
        try contentTypes.write(to: dir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        
        // _rels/.rels
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try rootRels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        
        // xl/_rels/workbook.xml.rels
        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
            <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
            <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet4.xml"/>
            <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        try workbookRels.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)
        
        // xl/styles.xml - properly structured styles
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <fonts count="2">
                <font>
                    <sz val="11"/>
                    <name val="Calibri"/>
                </font>
                <font>
                    <sz val="11"/>
                    <name val="Calibri"/>
                    <b/>
                </font>
            </fonts>
            <fills count="2">
                <fill>
                    <patternFill patternType="none"/>
                </fill>
                <fill>
                    <patternFill patternType="gray125"/>
                </fill>
            </fills>
            <borders count="1">
                <border>
                    <left/>
                    <right/>
                    <top/>
                    <bottom/>
                    <diagonal/>
                </border>
            </borders>
            <cellStyleXfs count="1">
                <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
            </cellStyleXfs>
            <cellXfs count="2">
                <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
                <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
            </cellXfs>
            <cellStyles count="1">
                <cellStyle name="Normal" xfId="0" builtinId="0"/>
            </cellStyles>
        </styleSheet>
        """
        try styles.write(to: xlDir.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)
        
        // xl/workbook.xml
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets>
                <sheet name="Registry" sheetId="1" r:id="rId1"/>
                <sheet name="Currencies" sheetId="2" r:id="rId2"/>
                <sheet name="Products" sheetId="3" r:id="rId3"/>
                <sheet name="Groups" sheetId="4" r:id="rId4"/>
            </sheets>
        </workbook>
        """
        try workbook.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)
        
        // Create the 4 worksheets
        let sheet1 = createRegistrySheet(event: event)
        try sheet1.write(to: worksheetsDir.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)
        
        let sheet2 = createCurrenciesSheet(event: event)
        try sheet2.write(to: worksheetsDir.appendingPathComponent("sheet2.xml"), atomically: true, encoding: .utf8)
        
        let sheet3 = createProductsSummarySheet(event: event)
        try sheet3.write(to: worksheetsDir.appendingPathComponent("sheet3.xml"), atomically: true, encoding: .utf8)
        
        let sheet4 = createGroupsSheet(event: event)
        try sheet4.write(to: worksheetsDir.appendingPathComponent("sheet4.xml"), atomically: true, encoding: .utf8)
    }
    
    // MARK: - Sheet 1: Registry
    
    private static func createRegistrySheet(event: Event) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <dimension ref="A1"/>
            <sheetViews>
                <sheetView workbookViewId="0">
                    <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
                </sheetView>
            </sheetViews>
            <sheetData>
        
        """
        
        // Get all products
        let allProducts = event.products.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        
        // Header row (row 1) with bold styling
        xml += "<row r=\"1\">"
        let headers = ["TX ID", "TX Date", "TX Time", "Payment Method", "Currency", "Total", "Discount", "Subtotal", "Note", "Email"]
        for (index, header) in headers.enumerated() {
            xml += "<c r=\"\(columnLetter(index))1\" s=\"1\" t=\"inlineStr\"><is><t>\(xmlEscape(header))</t></is></c>"
        }
        // Add product columns
        for (index, product) in allProducts.enumerated() {
            let colIndex = headers.count + index
            let productHeader = product.subgroup != nil ? "\(product.name) (\(product.subgroup!))" : product.name
            xml += "<c r=\"\(columnLetter(colIndex))1\" s=\"1\" t=\"inlineStr\"><is><t>\(xmlEscape(productHeader))</t></is></c>"
        }
        xml += "</row>\n"
        
        // Data rows
        let transactions = event.transactions.sorted { $0.timestamp < $1.timestamp }
        for (txIndex, transaction) in transactions.enumerated() {
            let rowNum = txIndex + 2
            xml += "<row r=\"\(rowNum)\">"
            
            var colNum = 0
            
            // TX ID
            let txId = transaction.transactionRef ?? String(transaction.id.uuidString.prefix(5).uppercased())
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\" t=\"inlineStr\"><is><t>\(xmlEscape(txId))</t></is></c>"
            colNum += 1
            
            // TX Date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\" t=\"inlineStr\"><is><t>\(dateFormatter.string(from: transaction.timestamp))</t></is></c>"
            colNum += 1
            
            // TX Time
            dateFormatter.dateFormat = "HH:mm:ss"
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\" t=\"inlineStr\"><is><t>\(dateFormatter.string(from: transaction.timestamp))</t></is></c>"
            colNum += 1
            
            // Payment Method
            let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\" t=\"inlineStr\"><is><t>\(xmlEscape(methodName))</t></is></c>"
            colNum += 1
            
            // Currency
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\" t=\"inlineStr\"><is><t>\(transaction.currencyCode)</t></is></c>"
            colNum += 1
            
            // Total
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\"><v>\(formatDecimalXML(transaction.totalAmount))</v></c>"
            colNum += 1
            
            // Discount
            let lineItemsTotal = transaction.lineItems.reduce(Decimal(0)) { $0 + $1.subtotal }
            let discount = lineItemsTotal - transaction.totalAmount
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\"><v>\(formatDecimalXML(discount))</v></c>"
            colNum += 1
            
            // Subtotal
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\"><v>\(formatDecimalXML(lineItemsTotal))</v></c>"
            colNum += 1
            
            // Note
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\" t=\"inlineStr\"><is><t>\(xmlEscape(transaction.note ?? ""))</t></is></c>"
            colNum += 1
            
            // Email
            xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\" t=\"inlineStr\"><is><t>\(xmlEscape(transaction.receiptEmail ?? ""))</t></is></c>"
            colNum += 1
            
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
                xml += "<c r=\"\(columnLetter(colNum))\(rowNum)\"><v>\(qty)</v></c>"
                colNum += 1
            }
            
            xml += "</row>\n"
        }
        
        xml += """
            </sheetData>
        </worksheet>
        """
        
        return xml
    }
    
    // MARK: - Sheet 2: Products Summary
    
    private static func createProductsSummarySheet(event: Event) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <dimension ref="A1"/>
            <sheetViews>
                <sheetView workbookViewId="0">
                    <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
                </sheetView>
            </sheetViews>
            <sheetData>
        
        """
        
        // Header row with bold styling
        xml += "<row r=\"1\">"
        let headers = ["Product", "Subgroup", "Qty Sold", "Total Amount"]
        for (index, header) in headers.enumerated() {
            xml += "<c r=\"\(columnLetter(index))1\" s=\"1\" t=\"inlineStr\"><is><t>\(xmlEscape(header))</t></is></c>"
        }
        xml += "</row>\n"
        
        // Get main currency
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        let mainCurrencyCode = mainCurrency?.code ?? event.currencyCode
        
        // Aggregate product sales
        var productStats: [UUID: (name: String, subgroup: String?, quantity: Int, totalAmount: Decimal)] = [:]
        
        for transaction in event.transactions {
            for lineItem in transaction.lineItems {
                if let product = event.products.first(where: { 
                    $0.name == lineItem.productName
                }) {
                    let convertedAmount = convertToMainCurrency(lineItem.subtotal, from: transaction.currencyCode, event: event)
                    
                    if var stats = productStats[product.id] {
                        stats.quantity += lineItem.quantity
                        stats.totalAmount += convertedAmount
                        productStats[product.id] = stats
                    } else {
                        productStats[product.id] = (
                            name: lineItem.productName,
                            subgroup: product.subgroup,
                            quantity: lineItem.quantity,
                            totalAmount: convertedAmount
                        )
                    }
                }
            }
        }
        
        // Sort by category sortOrder, then product sortOrder
        let sortedProducts = productStats.sorted { (pair1, pair2) in
            guard let product1 = event.products.first(where: { $0.id == pair1.key }),
                  let product2 = event.products.first(where: { $0.id == pair2.key }) else {
                return pair1.value.name < pair2.value.name
            }
            
            // First sort by category sortOrder
            if let cat1 = product1.category, let cat2 = product2.category {
                if cat1.sortOrder != cat2.sortOrder {
                    return cat1.sortOrder < cat2.sortOrder
                }
            } else if product1.category != nil {
                return true
            } else if product2.category != nil {
                return false
            }
            
            // Then by product sortOrder
            return product1.sortOrder < product2.sortOrder
        }
        var grandTotal = Decimal(0)
        
        for (index, (_, stats)) in sortedProducts.enumerated() {
            let rowNum = index + 2
            xml += "<row r=\"\(rowNum)\">"
            xml += "<c r=\"A\(rowNum)\" t=\"inlineStr\"><is><t>\(xmlEscape(stats.name))</t></is></c>"
            xml += "<c r=\"B\(rowNum)\" t=\"inlineStr\"><is><t>\(xmlEscape(stats.subgroup ?? ""))</t></is></c>"
            xml += "<c r=\"C\(rowNum)\"><v>\(stats.quantity)</v></c>"
            xml += "<c r=\"D\(rowNum)\"><v>\(formatDecimalXML(stats.totalAmount))</v></c>"
            xml += "</row>\n"
            grandTotal += stats.totalAmount
        }
        
        // Total row
        let totalRow = sortedProducts.count + 3
        xml += "<row r=\"\(totalRow)\">"
        xml += "<c r=\"A\(totalRow)\" t=\"inlineStr\"><is><t>TOTAL</t></is></c>"
        xml += "<c r=\"B\(totalRow)\"><v></v></c>"
        xml += "<c r=\"C\(totalRow)\"><v></v></c>"
        xml += "<c r=\"D\(totalRow)\"><v>\(formatDecimalXML(grandTotal))</v></c>"
        xml += "</row>\n"
        
        xml += """
            </sheetData>
        </worksheet>
        """
        
        return xml
    }
    
    // MARK: - Sheet 3: Currencies
    
    private static func createCurrenciesSheet(event: Event) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <dimension ref="A1"/>
            <sheetViews>
                <sheetView workbookViewId="0">
                    <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
                </sheetView>
            </sheetViews>
            <sheetData>
        
        """
        
        // Header row with bold styling
        xml += "<row r=\"1\">"
        let headers = ["Currency", "Payment Method", "Qty of Transactions", "Total Amount"]
        for (index, header) in headers.enumerated() {
            xml += "<c r=\"\(columnLetter(index))1\" s=\"1\" t=\"inlineStr\"><is><t>\(xmlEscape(header))</t></is></c>"
        }
        xml += "</row>\n"
        
        // Aggregate by currency and payment method
        var stats: [String: (currency: String, paymentMethod: String, count: Int, total: Decimal)] = [:]
        
        for transaction in event.transactions {
            let methodName = paymentMethodName(transaction.paymentMethod, icon: transaction.paymentMethodIcon)
            let key = "\(transaction.currencyCode)-\(methodName)"
            
            if var existing = stats[key] {
                existing.count += 1
                existing.total += transaction.totalAmount
                stats[key] = existing
            } else {
                stats[key] = (
                    currency: transaction.currencyCode,
                    paymentMethod: methodName,
                    count: 1,
                    total: transaction.totalAmount
                )
            }
        }
        
        // Sort and output
        let sortedStats = stats.sorted { 
            if $0.value.currency == $1.value.currency {
                return $0.value.paymentMethod < $1.value.paymentMethod
            }
            return $0.value.currency < $1.value.currency
        }
        
        for (index, (_, stat)) in sortedStats.enumerated() {
            let rowNum = index + 2
            xml += "<row r=\"\(rowNum)\">"
            xml += "<c r=\"A\(rowNum)\" t=\"inlineStr\"><is><t>\(stat.currency)</t></is></c>"
            xml += "<c r=\"B\(rowNum)\" t=\"inlineStr\"><is><t>\(stat.paymentMethod)</t></is></c>"
            xml += "<c r=\"C\(rowNum)\"><v>\(stat.count)</v></c>"
            xml += "<c r=\"D\(rowNum)\"><v>\(formatDecimalXML(stat.total))</v></c>"
            xml += "</row>\n"
        }
        
        xml += """
            </sheetData>
        </worksheet>
        """
        
        return xml
    }
    
    // MARK: - Sheet 4: Groups
    
    private static func createGroupsSheet(event: Event) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <dimension ref="A1"/>
            <sheetViews>
                <sheetView workbookViewId="0">
                    <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
                </sheetView>
            </sheetViews>
            <sheetData>
        
        """
        
        var rowNum = 1
        
        // Section 1: By Type (Categories)
        xml += "<row r=\"\(rowNum)\"><c r=\"A\(rowNum)\" s=\"1\" t=\"inlineStr\"><is><t>BY TYPE</t></is></c></row>\n"
        rowNum += 1
        
        // Header row for categories
        xml += "<row r=\"\(rowNum)\">"
        xml += "<c r=\"A\(rowNum)\" s=\"1\" t=\"inlineStr\"><is><t>Category</t></is></c>"
        xml += "<c r=\"B\(rowNum)\" s=\"1\" t=\"inlineStr\"><is><t>Total Units</t></is></c>"
        xml += "<c r=\"C\(rowNum)\" s=\"1\" t=\"inlineStr\"><is><t>Total Amount</t></is></c>"
        xml += "</row>\n"
        rowNum += 1
        
        // Aggregate by category
        var categoryStats: [UUID: (category: Category, units: Int, total: Decimal)] = [:]
        
        for transaction in event.transactions {
            for item in transaction.lineItems {
                if let category = item.product?.category {
                    let convertedAmount = convertToMainCurrency(item.subtotal, from: transaction.currencyCode, event: event)
                    
                    if var stats = categoryStats[category.id] {
                        stats.units += item.quantity
                        stats.total += convertedAmount
                        categoryStats[category.id] = stats
                    } else {
                        categoryStats[category.id] = (category: category, units: item.quantity, total: convertedAmount)
                    }
                }
            }
        }
        
        let sortedCategories = categoryStats.sorted { $0.value.category.sortOrder < $1.value.category.sortOrder }
        
        for (_, stat) in sortedCategories {
            xml += "<row r=\"\(rowNum)\">"
            xml += "<c r=\"A\(rowNum)\" t=\"inlineStr\"><is><t>\(xmlEscape(stat.category.name))</t></is></c>"
            xml += "<c r=\"B\(rowNum)\"><v>\(stat.units)</v></c>"
            xml += "<c r=\"C\(rowNum)\"><v>\(formatDecimalXML(stat.total))</v></c>"
            xml += "</row>\n"
            rowNum += 1
        }
        
        // Empty row separator
        rowNum += 1
        
        // Section 2: By Subgroup
        xml += "<row r=\"\(rowNum)\"><c r=\"A\(rowNum)\" s=\"1\" t=\"inlineStr\"><is><t>BY SUBGROUP</t></is></c></row>\n"
        rowNum += 1
        
        // Header row for subgroups
        xml += "<row r=\"\(rowNum)\">"
        xml += "<c r=\"A\(rowNum)\" s=\"1\" t=\"inlineStr\"><is><t>Subgroup</t></is></c>"
        xml += "<c r=\"B\(rowNum)\" s=\"1\" t=\"inlineStr\"><is><t>Total Units</t></is></c>"
        xml += "<c r=\"C\(rowNum)\" s=\"1\" t=\"inlineStr\"><is><t>Total Amount</t></is></c>"
        xml += "</row>\n"
        rowNum += 1
        
        // Aggregate by subgroup
        var subgroupStats: [String: (units: Int, total: Decimal)] = [:]
        
        for transaction in event.transactions {
            for item in transaction.lineItems {
                if let subgroup = item.subgroup, !subgroup.isEmpty {
                    let convertedAmount = convertToMainCurrency(item.subtotal, from: transaction.currencyCode, event: event)
                    
                    if var stats = subgroupStats[subgroup] {
                        stats.units += item.quantity
                        stats.total += convertedAmount
                        subgroupStats[subgroup] = stats
                    } else {
                        subgroupStats[subgroup] = (units: item.quantity, total: convertedAmount)
                    }
                }
            }
        }
        
        let sortedSubgroups = subgroupStats.sorted { $0.key < $1.key }
        
        for (subgroup, stat) in sortedSubgroups {
            xml += "<row r=\"\(rowNum)\">"
            xml += "<c r=\"A\(rowNum)\" t=\"inlineStr\"><is><t>\(xmlEscape(subgroup))</t></is></c>"
            xml += "<c r=\"B\(rowNum)\"><v>\(stat.units)</v></c>"
            xml += "<c r=\"C\(rowNum)\"><v>\(formatDecimalXML(stat.total))</v></c>"
            xml += "</row>\n"
            rowNum += 1
        }
        
        xml += """
            </sheetData>
        </worksheet>
        """
        
        return xml
    }
    
    // MARK: - Helpers
    
    private static func paymentMethodName(_ method: PaymentMethod, icon: String? = nil) -> String {
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
    
    private static func columnLetter(_ index: Int) -> String {
        var col = index
        var result = ""
        while col >= 0 {
            result = String(UnicodeScalar(65 + (col % 26))!) + result
            col = col / 26 - 1
            if col < 0 { break }
        }
        return result
    }
    
    private static func xmlEscape(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    
    private static func formatDecimalXML(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ""
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    }
    
    
    private static func convertToMainCurrency(_ amount: Decimal, from currencyCode: String, event: Event) -> Decimal {
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
