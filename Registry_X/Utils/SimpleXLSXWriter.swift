import Foundation

/// Minimal Excel XLSX writer with proven XML structure
class SimpleXLSXWriter {
    
    struct Worksheet {
        let name: String
        var rows: [[CellValue]] = []
        var frozenRows: Int = 0
    }
    
    enum CellValue {
        case text(String, bold: Bool = false)
        case number(Double)
        case decimal(Decimal)
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
    
    func generateXLSX() throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create structure
        let xlDir = tempDir.appendingPathComponent("xl")
        let relsDir = tempDir.appendingPathComponent("_rels")
        let xlRelsDir = xlDir.appendingPathComponent("_rels")
        let worksheetsDir = xlDir.appendingPathComponent("worksheets")
        
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worksheetsDir, withIntermediateDirectories: true)
        
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
        
        // xl/worksheets/sheetN.xml
        for (index, worksheet) in worksheets.enumerated() {
            let sheetXML = createWorksheet(worksheet, index: index)
            try sheetXML.write(to: worksheetsDir.appendingPathComponent("sheet\(index + 1).xml"), atomically: true, encoding: .utf8)
        }
        
        // Create ZIP
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
        try zipDirectory(tempDir, to: zipURL)
        
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
            xml += "    <Override Part Name=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>\n"
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
        
        """
        
        for i in 1...worksheets.count {
            xml += "    <Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>\n"
        }
        
        let stylesId = worksheets.count + 1
        let stringsId = worksheets.count + 2
        
        xml += "    <Relationship Id=\"rId\(stylesId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>\n"
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
            xml += "        <sheet name=\"\(xmlEscape(worksheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>\n"
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
        
        xml += """
            </sheetViews>
            <sheetData>
        
        """
        
        for (rowIndex, row) in worksheet.rows.enumerated() {
            let rowNum = rowIndex + 1
            xml += "        <row r=\"\(rowNum)\">\n"
            
            for (colIndex, cell) in row.enumerated() {
                let cellRef = "\(columnLetter(colIndex))\(rowNum)"
                
                switch cell {
                case .text(let value, let bold):
                    let style = bold ? " s=\"1\"" : ""
                    xml += "            <c r=\"\(cellRef)\"\(style) t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>\n"
                    
                case .number(let value):
                    xml += "            <c r=\"\(cellRef)\"><v>\(value)</v></c>\n"
                    
                case .decimal(let value):
                    let formatted = NSDecimalNumber(decimal: value).doubleValue
                    xml += "            <c r=\"\(cellRef)\"><v>\(formatted)</v></c>\n"
                    
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
    
    // MARK: - Utilities
    
    private func columnLetter(_ index: Int) -> String {
        var num = index
        var result = ""
        while num >= 0 {
            result = String(UnicodeScalar(65 + (num % 26))!) + result
            num = num / 26 - 1
            if num < 0 { break }
        }
        return result
    }
    
    private func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    private func zipDirectory(_ sourceURL: URL, to destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var capturedError: Error?
        
        coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: nil) { zippedURL in
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: zippedURL, to: destinationURL)
            } catch {
                capturedError = error
            }
        }
        
        if let error = capturedError {
            throw error
        }
    }
}
