import Foundation
import Testing
@testable import Domain

@Suite("Plik Excel (.xlsx)")
struct XLSXTests {
    /// Odczyt archiwum ZIP (metoda stored) — weryfikacja nagłówków, CRC i nazw plików.
    static func entries(_ zip: Data) throws -> [String: Data] {
        func u16(_ o: Int) -> Int { Int(zip[o]) | Int(zip[o + 1]) << 8 }
        func u32(_ o: Int) -> UInt32 { UInt32(zip[o]) | UInt32(zip[o + 1]) << 8 | UInt32(zip[o + 2]) << 16 | UInt32(zip[o + 3]) << 24 }
        var result: [String: Data] = [:]
        var o = 0
        while u32(o) == 0x04034b50 {
            let crc = u32(o + 14), size = Int(u32(o + 18)), nameLen = u16(o + 26), extra = u16(o + 28)
            let name = String(decoding: zip[(o + 30)..<(o + 30 + nameLen)], as: UTF8.self)
            let start = o + 30 + nameLen + extra
            let content = zip[start..<(start + size)]
            #expect(CRC32.checksum(Data(content)) == crc, "\(name)")
            result[name] = Data(content)
            o = start + size
        }
        #expect(u32(zip.count - 22) == 0x06054b50)
        #expect(u16(zip.count - 22 + 10) == result.count)
        return result
    }

    @Test("CRC32 zgodne ze standardem")
    func crc() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF43926)
    }

    @Test("Struktura pakietu i poprawny XML")
    func structure() throws {
        var sheet = Spreadsheet(sheetName: "Faktury <&>", columns: [.init("Nazwa", width: 20), .init("Kwota", width: 12), .init("Data", width: 12)],
                                rows: [[.text("Zażółć & \"cytat\" <tag>\u{0001}"), .amount(Decimal(string: "1234.56")!), .date(LocalDate(year: 2026, month: 10, day: 13)!)],
                                       [.text("B"), .amount(-10), .empty]])
        sheet.totalColumns = [1]
        let files = try Self.entries(sheet.xlsx())
        #expect(Set(files.keys) == ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
                                     "xl/styles.xml", "xl/worksheets/sheet1.xml"])
        for (name, data) in files {
            let parser = XMLParser(data: data)
            #expect(parser.parse(), "\(name): \(String(describing: parser.parserError))")
        }
        let xml = String(decoding: files["xl/worksheets/sheet1.xml"]!, as: UTF8.self)
        #expect(xml.contains("Zażółć &amp; &quot;cytat&quot; &lt;tag&gt;"))
        #expect(xml.contains("<v>1234.56</v>"))
        #expect(xml.contains("<v>46308</v>"), "2026-10-13 jako liczba seryjna Excela")
        #expect(xml.contains("<f>SUM(B2:B3)</f>"))
    }

    @Test("Nazwy kolumn Excela")
    func columnNames() {
        #expect(Spreadsheet.columnName(0) == "A")
        #expect(Spreadsheet.columnName(25) == "Z")
        #expect(Spreadsheet.columnName(26) == "AA")
        #expect(Spreadsheet.columnName(27) == "AB")
    }
}
