import Foundation

/// Dowolna wartość JSON — odpowiedzi KSeF bywają niejednorodne (różne nazwy
/// pól w wersjach API), a port musi zachować pythonową semantykę `a or b`.
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Decimal.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Prawdziwość w sensie Pythona.
    public var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return !s.isEmpty
        case .array(let a): return !a.isEmpty
        case .object(let o): return !o.isEmpty
        }
    }

    public subscript(key: String) -> JSONValue {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    /// `str(value)` dla prostych typów.
    public var stringValue: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "True" : "False"
        case .number(let n): return DecimalText.string(n)
        case .string(let s): return s
        default: return ""
        }
    }

    public var decimalValue: Decimal? {
        switch self {
        case .number(let n): return n
        case .string(let s): return DecimalText.parse(s)
        default: return nil
        }
    }

    /// `a or b or c` — pierwsza "prawdziwa" wartość albo ostatnia.
    public static func firstTruthy(_ values: JSONValue...) -> JSONValue {
        values.first(where: \.isTruthy) ?? values.last ?? .null
    }
}
