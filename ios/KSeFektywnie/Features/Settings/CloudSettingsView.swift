import SwiftUI

struct CloudSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var cloud = model.cloud
        Form {
            Section {
                Toggle("Zapisuj dane w katalogu", isOn: $cloud.isEnabled)
            } footer: {
                Text("Faktury (JSON i XML), pliki przelewów i wyciągi są zapisywane jako zwykłe pliki. Token KSeF nigdy nie trafia do katalogu.")
            }

            Section("Stan") {
                switch cloud.location {
                case .iCloud:
                    Label("iCloud Drive → KS-eFektywnie", systemImage: "icloud")
                case .local:
                    Label("Na tym iPhonie → KS-eFektywnie", systemImage: "iphone")
                    Text("iCloud Drive jest wyłączony albo niedostępny. Pliki są w aplikacji Pliki, w sekcji „Na moim iPhonie”, ale nie są kopią poza telefonem.")
                        .font(.footnote).foregroundStyle(.orange)
                case .unknown:
                    Label("Sprawdzanie…", systemImage: "hourglass")
                }
                if cloud.isSyncing { HStack { Text("Zapisywanie…"); Spacer(); ProgressView() } }
                if let last = cloud.lastSync {
                    LabeledContent("Ostatni zapis", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if let report = cloud.lastReport {
                    LabeledContent("Zmienione pliki", value: "\(report.written)")
                }
                if let error = cloud.lastError { Text(error).foregroundStyle(.red) }
                if let warning = cloud.otherDeviceWarning {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            Section {
                Button("Zapisz wszystko ponownie") { Task { await cloud.rewriteAll() } }
                    .disabled(!cloud.isEnabled || cloud.isSyncing)
            } footer: {
                Text("Przydatne, gdy pliki zostały usunięte z iCloud Drive ręcznie.")
            }
        }
        .navigationTitle("iCloud Drive")
    }
}
