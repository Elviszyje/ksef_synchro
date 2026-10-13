import Foundation
import Domain
import KSeFClient
import Persistence
import AppServices

/// Komunikaty błędów z warstw logiki (pisane po polsku) w języku interfejsu.
extension Error {
    var userMessage: String {
        switch self {
        case let e as KSeFError:
            switch e {
            case .rateLimited(let seconds):
                return String(localized: "KSeF ograniczył liczbę zapytań. Spróbuj ponownie za ok. \(max(1, seconds / 60)) min.")
            case .authentication(let message):
                return String(localized: "Błąd uwierzytelnienia w KSeF: \(message)")
            case .api(401, _):
                return String(localized: "KSeF odrzucił token (401). Sprawdź, czy token jest aktualny i wygenerowany dla tego NIP.")
            case .api(403, _):
                return String(localized: "Token nie ma wymaganych uprawnień (403). Wygeneruj token z uprawnieniem do przeglądania faktur.")
            case .api(let status, let message):
                return String(localized: "KSeF zwrócił błąd \(status): \(message)")
            case .invalidResponse(let message):
                return String(localized: "Nieoczekiwana odpowiedź KSeF: \(message)")
            case .missingToken:
                return String(localized: "Brak tokena KSeF. Uzupełnij go w Ustawieniach.")
            }
        case let e as StatementError:
            switch e {
            case .unrecognizedFormat: return String(localized: "Nie rozpoznano formatu pliku. Obsługiwane formaty: MT940 (SWIFT), CSV VeloBank, CSV Erste Bank.")
            case .unreadableEncoding: return String(localized: "Nie można odczytać pliku. Sprawdź kodowanie (UTF-8 lub Windows-1250).")
            case .emptyFile: return String(localized: "Pusty plik.")
            case .missingAmountColumn: return String(localized: "Nie znaleziono kolumny \"Kwota\" w pliku CSV.")
            }
        case let e as PaymentFileError:
            switch e {
            case .noInvoices: return String(localized: "Nie wybrano faktur.")
            case .invoiceNotPayable(let number): return String(localized: "Faktura \(number) nie jest „Do zapłaty” albo nie ma numeru rachunku.")
            case .paidInvoiceInBatch: return String(localized: "Nie można zresetować paczki — co najmniej jedna faktura ma status „Opłacona”.")
            }
        case let e as SalesError:
            switch e {
            case .duplicateNumber(let n): return String(localized: "Faktura o numerze \(n) już istnieje.")
            case .notEditable: return String(localized: "Fakturę można edytować tylko w statusie szkicu.")
            case .invalid: return String(localized: "Faktura ma niekompletne dane.")
            }
        case let e as SendError:
            switch e {
            case .notFound: return String(localized: "Nie znaleziono faktury.")
            case .notSendable: return String(localized: "Fakturę można wysłać tylko jako szkic albo po odrzuceniu przez KSeF.")
            case .environmentMismatch: return String(localized: "Szkic utworzono dla innego środowiska KSeF niż obecnie ustawione. Utwórz nową fakturę.")
            case .invalid: return String(localized: "Faktura ma niekompletne dane.")
            }
        case let e as FA3GeneratorError:
            switch e {
            case .noItems: return String(localized: "Dodaj co najmniej jedną pozycję.")
            case .missingBankAccount: return String(localized: "Wybierz rachunek do przelewu albo dodaj go w Ustawieniach.")
            case .missingExemptionBasis: return String(localized: "Pozycje ze stawką ZW wymagają podania podstawy prawnej zwolnienia z VAT.")
            }
        case let e as StatementRepositoryError:
            switch e {
            case .alreadyConfirmed: return String(localized: "Wyciąg jest już zatwierdzony.")
            case .nothingConfirmed: return String(localized: "Potwierdź co najmniej jedno dopasowanie przed zatwierdzeniem wyciągu.")
            }
        case is InvoiceStatusError:
            return String(localized: "Ta zmiana statusu jest niedozwolona.")
        case let e as URLError where e.code == .notConnectedToInternet || e.code == .networkConnectionLost:
            return String(localized: "Brak połączenia z internetem.")
        default:
            return localizedDescription
        }
    }
}
