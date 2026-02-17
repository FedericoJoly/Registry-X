import Foundation
import ZIPFoundation

/// Minimal Excel XLSX writer with proven XML structure
class SimpleXLSXWriter {
    
    struct Worksheet {
        let name: String
        var rows: [[CellValue]] = []
        var frozenRows: Int = 0
        var columnWidths: [Int: Double] = [:] // Column index to width in characters
    }
    
    enum CellValue {
        case text(String, bold: Bool = false, centered: Bool = false)
        case number(Double, bold: Bool = false)
        case decimal(Decimal)
        case currency(Decimal, currencyCode: String, bold: Bool = false) // Currency formatting
        case empty
    }
    
    private var worksheets: [Worksheet] = []
    
    func addWorksheet(name: String, frozenRows: Int = 0) -> Int {
        worksheets.append(Worksheet(name: name, frozenRows: frozenRows))
        return worksheets.count - 1
    }
    
    func addRow(to sheetIndex: Int, values: [CellValue]) {
        guard sheetIndex < worksheets.count else { return }
        worksheets[sheetIndex].rows.append(values)
    }
    
    func setColumnWidth(sheetIndex: Int, column: Int, width: Double) {
        guard sheetIndex < worksheets.count else { return }
        worksheets[sheetIndex].columnWidths[column] = width
    }
    
    func generateXLSX() throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create directory structure
        let relsDir = tempDir.appendingPathComponent("_rels")
        let xlDir = tempDir.appendingPathComponent("xl")
        let xlRelsDir = xlDir.appendingPathComponent("_rels")
        let xlWorksheetsDir = xlDir.appendingPathComponent("worksheets")
        
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlWorksheetsDir, withIntermediateDirectories: true)
        
        // [Content_Types].xml
        try createContentTypes().write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        
        // _rels/.rels
        try createRootRels().write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        
        // xl/_rels/workbook.xml.rels
        try createWorkbookRels().write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)
        
        // xl/workbook.xml
        try createWorkbook().write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)
        
        // xl/styles.xml
        try createStyles().write(to: xlDir.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)
        
        // xl/sharedStrings.xml
        try createSharedStrings().write(to: xlDir.appendingPathComponent("sharedStrings.xml"), atomically: true, encoding: .utf8)
        
        // xl/worksheets/sheet1.xml, sheet2.xml, ...
        for (index, worksheet) in worksheets.enumerated() {
            let sheetXML = createWorksheet(worksheet, index: index)
            let sheetPath = xlWorksheetsDir.appendingPathComponent("sheet\(index + 1).xml")
            try sheetXML.write(to: sheetPath, atomically: true, encoding: .utf8)
        }
        
        // Zip the directory
        let zipURL = tempDir.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).xlsx")
        try FileManager.default.zipItem(at: tempDir, to: zipURL, shouldKeepParent: false)
        
        let data = try Data(contentsOf: zipURL)
        try? FileManager.default.removeItem(at: zipURL)
        
        return data
    }
    
    // MARK: - XML Generation
    
    private func createContentTypes() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
            <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
        
        """
        
        for i in 1...worksheets.count {
            xml += "    <Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>\n"
        }
        
        xml += "</Types>"
        return xml
    }
    
    private func createRootRels() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }
    
    private func createWorkbookRels() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        
        """
        
        for i in 1...worksheets.count {
            xml += "    <Relationship Id=\"rId\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>\n"
        }
        
        let stringsId = worksheets.count + 2
        xml += "    <Relationship Id=\"rId\(stringsId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>\n"
        xml += "</Relationships>"
        
        return xml
    }
    
    private func createWorkbook() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets>
        
        """
        
        for (index, worksheet) in worksheets.enumerated() {
            xml += "        <sheet name=\"\(xmlEscape(worksheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 2)\"/>\n"
        }
        
        xml += """
            </sheets>
        </workbook>
        """
        
        return xml
    }
    
    private func createStyles() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <numFmts count="5">
                <numFmt numFmtId="164" formatCode="0.00"/>
                <numFmt numFmtId="165" formatCode="$#,##0.00"/>
                <numFmt numFmtId="166" formatCode="€#,##0.00"/>
                <numFmt numFmtId="167" formatCode="£#,##0.00"/>
                <numFmt numFmtId="168" formatCode="0"/>
            </numFmts>
            <fonts count="2">
                <font>
                    <sz val="12"/>
                    <name val="Arial"/>
                </font>
                <font>
                    <sz val="12"/>
                    <name val="Arial"/>
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
            <cellXfs count="13">
                <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
                <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
                <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1">
                    <alignment horizontal="center"/>
                </xf>
                <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
                <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
                <xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
                <xf numFmtId="167" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
                <xf numFmtId="168" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
                <xf numFmtId="168" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
                <xf numFmtId="165" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
                <xf numFmtId="166" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
                <xf numFmtId="167" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
                <xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
            </cellXfs>
            <cellStyles count="1">
                <cellStyle name="Normal" xfId="0" builtinId="0"/>
            </cellStyles>
        </styleSheet>
        """
    }
    
    private func createSharedStrings() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="0" uniqueCount="0"/>
        """
    }
    
    private func createWorksheet(_ worksheet: Worksheet, index: Int) -> String {
        let maxRow = worksheet.rows.count
        let maxCol = worksheet.rows.map { $0.count }.max() ?? 0
        let dimension = maxRow > 0 && maxCol > 0 ? "A1:\(columnLetter(maxCol - 1))\(maxRow)" : "A1"
        
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <dimension ref="\(dimension)"/>
            <sheetViews>
        
        """
        
        if worksheet.frozenRows > 0 {
            xml += "        <sheetView workbookViewId=\"0\">\n"
            xml += "            <pane ySplit=\"\(worksheet.frozenRows)\" topLeftCell=\"A\(worksheet.frozenRows + 1)\" activePane=\"bottomLeft\" state=\"frozen\"/>\n"
            xml += "        </sheetView>\n"
        } else {
            xml += "        <sheetView workbookViewId=\"0\"/>\n"
        }
        
        xml += "    </sheetViews>\n"
        
        // Add column widths if specified
        if !worksheet.columnWidths.isEmpty {
            xml += "    <cols>\n"
            for (colIndex, width) in worksheet.columnWidths.sorted(by: { $0.key < $1.key }) {
                let colNum = colIndex + 1
                xml += "        <col min=\"\(colNum)\" max=\"\(colNum)\" width=\"\(width)\" customWidth=\"1\"/>\n"
            }
            xml += "    </cols>\n"
        }
        
        xml += "    <sheetData>\n"
        
        for (rowIndex, row) in worksheet.rows.enumerated() {
            let rowNum = rowIndex + 1
            xml += "        <row r=\"\(rowNum)\">\n"
            
            for (colIndex, cell) in row.enumerated() {
                let cellRef = "\(columnLetter(colIndex))\(rowNum)"
                
                switch cell {
                case .text(let value, let bold, let centered):
                    let style: String
                    if bold && centered {
                        style = " s=\"2\""
                    } else if bold {
                        style = " s=\"1\""
                    } else {
                        style = ""
                    }
                    xml += "            <c r=\"\(cellRef)\"\(style) t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>\n"
                    
                case .number(let value, let bold):
                    // Style 7/8 = integer, Style 3/12 = decimal (8/12 = bold)
                    let style: String
                    if value == floor(value) {
                        style = bold ? "8" : "7"
                    } else {
                        style = bold ? "12" : "3"
                    }
                    xml += "            <c r=\"\(cellRef)\" s=\"\(style)\"><v>\(value)</v></c>\n"
                    
                case .decimal(let value):
                    let formatted = NSDecimalNumber(decimal: value).doubleValue
                    xml += "            <c r=\"\(cellRef)\" s=\"3\"><v>\(formatted)</v></c>\n"
                    
                case .currency(let value, let currencyCode, let bold):
                    let formatted = NSDecimalNumber(decimal: value).doubleValue
                    // Styles: 4/9=USD, 5/10=EUR, 6/11=GBP (9/10/11 = bold)
                    let style: String
                    if bold {
                        style = currencyCode == "USD" ? "9" : currencyCode == "EUR" ? "10" : currencyCode == "GBP" ? "11" : "12"
                    } else {
                        style = currencyCode == "USD" ? "4" : currencyCode == "EUR" ? "5" : currencyCode == "GBP" ? "6" : "3"
                    }
                    xml += "            <c r=\"\(cellRef)\" s=\"\(style)\"><v>\(formatted)</v></c>\n"
                    
                case .empty:
                    xml += "            <c r=\"\(cellRef)\"/>\n"
                }
            }
            
            xml += "        </row>\n"
        }
        
        xml += """
            </sheetData>
        </worksheet>
        """
        
        return xml
    }
    
    // MARK: - Helpers
    
    private func columnLetter(_ index: Int) -> String {
        var column = index
        var result = ""
        while column >= 0 {
            result = String(UnicodeScalar(65 + (column % 26))!) + result
            column = (column / 26) - 1
        }
        return result
    }
    
    private func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
