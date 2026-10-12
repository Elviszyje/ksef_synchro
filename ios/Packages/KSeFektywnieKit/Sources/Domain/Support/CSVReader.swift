import Foundation

/// Czytnik CSV zachowujący się jak `csv.reader` z Pythona (dialekt domyślny,
/// `strict=False`): cudzysłów jest specjalny tylko na początku pola, `""` w
/// polu cytowanym to cudzysłów, znak po zamykającym cudzysłowie trafia do pola.
enum CSVReader {
    static func rows(_ text: String, delimiter: Character = ",") -> [[String]] {
        enum State { case startRecord, startField, inField, inQuoted, quoteInQuoted }
        let delim = delimiter.unicodeScalars.first!
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var state = State.startRecord
        var scalars = Array(text.unicodeScalars)
        scalars.append("\0") // wartownik końca danych
        var i = 0

        func saveField() { row.append(String(field)); field = String.UnicodeScalarView() }
        func endRecord() { rows.append(row); row = [] }

        while i < scalars.count {
            let c = scalars[i]
            let isEOF = i == scalars.count - 1
            if isEOF {
                if state == .inQuoted || state == .quoteInQuoted || state == .inField || state == .startField || !field.isEmpty {
                    if state != .startRecord { saveField(); endRecord() }
                }
                break
            }
            let isNewline = c == "\n" || c == "\r"
            switch state {
            case .startRecord:
                if isNewline {
                    // pusta linia — Python zwraca [] (odfiltrowujemy ją wyżej)
                    if c == "\r", scalars[i + 1] == "\n" { i += 1 }
                    rows.append([])
                    i += 1
                    continue
                }
                state = .startField
                continue
            case .startField:
                if c == "\"" { state = .inQuoted }
                else if c == delim { saveField() }
                else if isNewline {
                    saveField(); endRecord()
                    if c == "\r", scalars[i + 1] == "\n" { i += 1 }
                    state = .startRecord
                } else { field.append(c); state = .inField }
            case .inField:
                if c == delim { saveField(); state = .startField }
                else if isNewline {
                    saveField(); endRecord()
                    if c == "\r", scalars[i + 1] == "\n" { i += 1 }
                    state = .startRecord
                } else { field.append(c) }
            case .inQuoted:
                if c == "\"" { state = .quoteInQuoted } else { field.append(c) }
            case .quoteInQuoted:
                if c == "\"" { field.append(c); state = .inQuoted }
                else if c == delim { saveField(); state = .startField }
                else if isNewline {
                    saveField(); endRecord()
                    if c == "\r", scalars[i + 1] == "\n" { i += 1 }
                    state = .startRecord
                } else { field.append(c); state = .inField }
            }
            i += 1
        }
        return rows
    }

    /// `[row for row in reader if any(c.strip() for c in row)]`
    static func nonEmptyRows(_ text: String, delimiter: Character = ",") -> [[String]] {
        rows(text, delimiter: delimiter).filter { $0.contains { !PyText.strip($0).isEmpty } }
    }
}
