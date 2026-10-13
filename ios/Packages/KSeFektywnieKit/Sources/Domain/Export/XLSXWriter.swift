import Foundation

/// Prosty arkusz Excel (.xlsx): jedna karta, nagłówek, wiersze danych i wiersz sumy.
public struct Spreadsheet: Sendable {
    public enum Cell: Hashable, Sendable {
        case text(String)
        case amount(Decimal)
        case date(LocalDate)
        case empty
    }

    public struct Column: Hashable, Sendable {
        public var title: String
        public var width: Double
        public init(_ title: String, width: Double) {
            self.title = title
            self.width = width
        }
    }

    public var sheetName: String
    public var columns: [Column]
    public var rows: [[Cell]]
    /// Wiersze do wyróżnienia (np. przeterminowane), indeksy w `rows`.
    public var highlightedRows: Set<Int> = []
    /// Kolumny sumowane w wierszu podsumowania (formuła SUM), z etykietą w pierwszej kolumnie.
    public var totalColumns: [Int] = []
    public var totalLabel = "Razem"

    public init(sheetName: String, columns: [Column], rows: [[Cell]]) {
        self.sheetName = sheetName
        self.columns = columns
        self.rows = rows
    }

    /// Plik .xlsx (Office Open XML).
    public func xlsx() -> Data {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(rootRels.utf8))
        zip.add("xl/workbook.xml", Data(workbook.utf8))
        zip.add("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8))
        zip.add("xl/styles.xml", Data(styles.utf8))
        zip.add("xl/worksheets/sheet1.xml", Data(sheet.utf8))
        return zip.finish()
    }

    // MARK: Style (indeksy w cellXfs)
    // 0 domyślny, 1 nagłówek, 2 kwota, 3 data, 4 tekst wyróżniony, 5 kwota wyróżniona, 6 data wyróżniona, 7 suma etykieta, 8 suma kwota

    func style(_ cell: Cell, highlighted: Bool) -> Int {
        switch cell {
        case .amount: highlighted ? 5 : 2
        case .date: highlighted ? 6 : 3
        case .text, .empty: highlighted ? 4 : 0
        }
    }

    static func columnName(_ index: Int) -> String {
        var n = index + 1, name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(UnicodeScalar(65 + r)!) + name
            n = (n - 1) / 26
        }
        return name
    }

    static func escape(_ s: String) -> String {
        // Znaki sterujące poza tab/nową linią są niedozwolone w XML 1.0.
        let cleaned = String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" }))
        return cleaned.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Liczba seryjna daty w Excelu (1900-01-01 = 1, z historycznym 29.02.1900).
    static func serial(_ d: LocalDate) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let base = utc.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        let date = utc.date(from: DateComponents(year: d.year, month: d.month, day: d.day))!
        return Int((date.timeIntervalSince(base) / 86_400).rounded())
    }

    func cellXML(_ cell: Cell, ref: String, style: Int) -> String {
        switch cell {
        case .text(let s):
            return "<c r=\"\(ref)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(Self.escape(s))</t></is></c>"
        case .amount(let d):
            return "<c r=\"\(ref)\" s=\"\(style)\"><v>\(DecimalText.string(d))</v></c>"
        case .date(let d):
            return "<c r=\"\(ref)\" s=\"\(style)\"><v>\(Self.serial(d))</v></c>"
        case .empty:
            return "<c r=\"\(ref)\" s=\"\(style)\"/>"
        }
    }

    var sheet: String {
        let lastColumn = Self.columnName(columns.count - 1)
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="15"/>
        <cols>
        """
        for (i, column) in columns.enumerated() {
            xml += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(column.width)\" customWidth=\"1\"/>"
        }
        xml += "</cols><sheetData>"
        xml += "<row r=\"1\" ht=\"30\" customHeight=\"1\">"
        for (i, column) in columns.enumerated() {
            xml += cellXML(.text(column.title), ref: "\(Self.columnName(i))1", style: 1)
        }
        xml += "</row>"
        for (r, row) in rows.enumerated() {
            let rowNumber = r + 2
            xml += "<row r=\"\(rowNumber)\">"
            for (c, cell) in row.enumerated() {
                xml += cellXML(cell, ref: "\(Self.columnName(c))\(rowNumber)", style: style(cell, highlighted: highlightedRows.contains(r)))
            }
            xml += "</row>"
        }
        if !totalColumns.isEmpty && !rows.isEmpty {
            let totalRow = rows.count + 2
            xml += "<row r=\"\(totalRow)\">"
            xml += cellXML(.text(totalLabel), ref: "A\(totalRow)", style: 7)
            for c in totalColumns {
                let col = Self.columnName(c)
                xml += "<c r=\"\(col)\(totalRow)\" s=\"8\"><f>SUM(\(col)2:\(col)\(rows.count + 1))</f></c>"
            }
            xml += "</row>"
        }
        xml += "</sheetData>"
        xml += "<autoFilter ref=\"A1:\(lastColumn)\(max(1, rows.count + 1))\"/>"
        xml += "<pageMargins left=\"0.5\" right=\"0.5\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/>"
        xml += "<pageSetup orientation=\"landscape\" paperSize=\"9\" fitToWidth=\"1\" fitToHeight=\"0\"/>"
        xml += "</worksheet>"
        return xml
    }

    var styles: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0.00"/><numFmt numFmtId="165" formatCode="yyyy-mm-dd"/></numFmts>
        <fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1A56DB"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFEE2E2"/><bgColor indexed="64"/></patternFill></fill></fills>
        <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top style="thin"><color rgb="FF9CA3AF"/></top><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="9">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1"/>
        <xf numFmtId="164" fontId="0" fillId="3" borderId="0" xfId="0" applyNumberFormat="1" applyFill="1"/>
        <xf numFmtId="165" fontId="0" fillId="3" borderId="0" xfId="0" applyNumberFormat="1" applyFill="1"/>
        <xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
        <xf numFmtId="164" fontId="2" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
        """
    }

    var workbook: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(Self.escape(String(sheetName.prefix(31))))" sheetId="1" r:id="rId1"/></sheets>
        <definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'\(Self.escape(String(sheetName.prefix(31))))'!$A$1:$\(Self.columnName(columns.count - 1))$\(max(1, rows.count + 1))</definedName></definedNames>
        </workbook>
        """
    }

    let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """
}
