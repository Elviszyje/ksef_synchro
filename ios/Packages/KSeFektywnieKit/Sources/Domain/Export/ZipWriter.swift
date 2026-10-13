import Foundation

/// Minimalny zapis archiwum ZIP (metoda „stored”, bez kompresji) — wystarcza dla plików .xlsx.
/// Foundation na iOS nie ma API do tworzenia archiwów ZIP.
struct ZipWriter {
    private var data = Data()
    private var central = Data()
    private var count: UInt16 = 0

    mutating func add(_ path: String, _ content: Data) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(content)
        let offset = UInt32(data.count)
        // Nagłówek lokalny
        data.append(le32: 0x04034b50)
        data.append(le16: 20)          // wersja do rozpakowania
        data.append(le16: 0x0800)      // flaga: nazwy w UTF-8
        data.append(le16: 0)           // metoda: stored
        data.append(le16: 0); data.append(le16: 0x21) // czas/data (1980-01-01)
        data.append(le32: crc)
        data.append(le32: UInt32(content.count))
        data.append(le32: UInt32(content.count))
        data.append(le16: UInt16(name.count))
        data.append(le16: 0)
        data.append(name)
        data.append(content)
        // Wpis katalogu centralnego
        central.append(le32: 0x02014b50)
        central.append(le16: 20); central.append(le16: 20)
        central.append(le16: 0x0800); central.append(le16: 0)
        central.append(le16: 0); central.append(le16: 0x21)
        central.append(le32: crc)
        central.append(le32: UInt32(content.count)); central.append(le32: UInt32(content.count))
        central.append(le16: UInt16(name.count))
        central.append(le16: 0); central.append(le16: 0); central.append(le16: 0); central.append(le16: 0)
        central.append(le32: 0)
        central.append(le32: offset)
        central.append(name)
        count += 1
    }

    func finish() -> Data {
        var out = data
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x06054b50)
        out.append(le16: 0); out.append(le16: 0)
        out.append(le16: count); out.append(le16: count)
        out.append(le32: UInt32(central.count))
        out.append(le32: centralOffset)
        out.append(le16: 0)
        return out
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func append(le16 value: UInt16) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
}
