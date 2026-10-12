import Foundation
import Testing
@testable import Domain

/// Dostęp do golden files wygenerowanych przez `manage.py export_ios_fixtures`.
enum Fixtures {
    static let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

    static func url(_ path: String) -> URL { root.appending(path: path) }

    static func data(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }

    static func json(_ path: String) throws -> Any { try JSONSerialization.jsonObject(with: data(path)) }

    static func files(in dir: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url(dir), includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Porównania pól z JSON-a Django.
func expectDecimal(_ actual: Decimal?, _ expected: Any?, _ field: String, sourceLocation: SourceLocation = #_sourceLocation) {
    if expected == nil || expected is NSNull {
        #expect(actual == nil, "\(field): oczekiwano null", sourceLocation: sourceLocation)
        return
    }
    let parsed = DecimalText.parse(expected as! String)
    #expect(actual == parsed, "\(field): \(String(describing: actual)) ≠ \(expected!)", sourceLocation: sourceLocation)
}

func expectString(_ actual: String?, _ expected: Any?, _ field: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let exp: String? = (expected is NSNull) ? nil : expected as? String
    #expect(actual == exp, "\(field): \(String(describing: actual)) ≠ \(String(describing: exp))", sourceLocation: sourceLocation)
}

func expectDate(_ actual: LocalDate?, _ expected: Any?, _ field: String, sourceLocation: SourceLocation = #_sourceLocation) {
    expectString(actual?.iso, expected, field, sourceLocation: sourceLocation)
}
