import Foundation

/// Encje XML/HTML pozostawione w tekście, gdy wystawca zakodował nazwę podwójnie
/// (w XML jest `K&amp;amp;K`, po parsowaniu zostaje `K&amp;K`). KSeF zwraca takie
/// nazwy też w metadanych. Dekodowanie powtarzane do ustalenia (najwyżej 3 razy).
/// Port `html.unescape` z `apps/ksef/parser.py` i `sales_parser.py` (zakres: encje XML i numeryczne).
public enum XMLEntities {
    static let named: [Substring: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}"]

    public static func decode(_ text: String) -> String {
        var current = text
        for _ in 0..<3 {
            guard current.contains("&") else { return current }
            let next = decodeOnce(current)
            if next == current { return current }
            current = next
        }
        return current
    }

    static func decodeOnce(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let afterAmp = rest.index(after: amp)
            if let semi = rest[afterAmp...].prefix(10).firstIndex(of: ";"),
               let decoded = entity(rest[afterAmp..<semi]) {
                result += decoded
                rest = rest[rest.index(after: semi)...]
            } else {
                result += "&"
                rest = rest[afterAmp...]
            }
        }
        return result + rest
    }

    static func entity(_ name: Substring) -> String? {
        if let named = named[name] { return named }
        guard name.first == "#" else { return nil }
        let digits = name.dropFirst()
        let value: UInt32? = digits.first == "x" || digits.first == "X"
            ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
        return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}
