import Foundation

/// Operacje na kwotach w semantyce `decimal.Decimal` z Pythona.
public enum DecimalText {
    /// Ścisłe parsowanie jak `Decimal(str)`; zwraca nil zamiast `InvalidOperation`.
    /// `Decimal(string:)` z Foundation akceptuje śmieci na końcu ("12abc" → 12), więc nie wystarcza.
    public static func parse(_ text: String) -> Decimal? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard s.range(of: #"^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Kanoniczny zapis kwoty z kropką, bez separatorów tysięcy.
    public static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

extension Decimal {
    /// Zaokrąglenie do `scale` miejsc. Domyślnie bankierskie (ROUND_HALF_EVEN),
    /// czyli tak jak `round(Decimal)` i `Decimal.quantize` w Pythonie.
    public func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }

    /// Wartość w groszach (`int(round(amount * 100))`).
    public var minorUnits: Int64 {
        NSDecimalNumber(decimal: (self * 100).rounded(scale: 0)).int64Value
    }

    public init(minorUnits: Int64) {
        self = Decimal(minorUnits) / 100
    }
}
