import SwiftUI
import Domain
import KSeFClient

/// Pobranie nazwy i adresu podmiotu po NIP z Białej Listy MF (formularz faktury, onboarding).
/// Z `autoLookup` dane pobierają się same, gdy wpisany NIP stanie się poprawny.
struct WhiteListLookup: View {
    let nip: String
    var autoLookup = false
    let onFound: (RegisteredTaxpayer) -> Void

    private enum Phase: Equatable {
        case idle, loading, notFound
        case found(RegisteredTaxpayer)
        case failed(String)
    }

    @State private var phase: Phase = .idle

    private var digits: String { nip.filter(\.isNumber) }
    private var isValid: Bool { Validation.isValidNIP(digits) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { Task { await lookup() } } label: {
                HStack {
                    Label("Pobierz dane z Białej Listy", systemImage: "building.columns")
                    Spacer()
                    if phase == .loading { ProgressView() }
                }
            }
            .disabled(!isValid || phase == .loading)
            .accessibilityIdentifier("whitelist-lookup")
            status
        }
        .task(id: digits) {
            phase = .idle
            if autoLookup && isValid { await lookup() }
        }
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .found(let taxpayer):
            if taxpayer.isActiveVATPayer {
                Label("Czynny podatnik VAT — dane uzupełnione", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label("Status VAT: \(taxpayer.vatStatus.isEmpty ? "—" : taxpayer.vatStatus) — dane uzupełnione",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        case .notFound:
            Label("Brak w wykazie podatników VAT — wpisz dane ręcznie.", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.red)
        case .idle, .loading:
            EmptyView()
        }
    }

    private func lookup() async {
        phase = .loading
        do {
            if let taxpayer = try await WhiteListClient().lookup(nip: digits) {
                guard !Task.isCancelled else { return }
                onFound(taxpayer)
                phase = .found(taxpayer)
            } else {
                phase = .notFound
            }
        } catch {
            if !Task.isCancelled { phase = .failed(error.userMessage) }
        }
    }
}
