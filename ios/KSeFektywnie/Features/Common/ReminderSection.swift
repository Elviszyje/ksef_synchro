import SwiftUI
import EventKit
import Domain
import Persistence

/// Prezentuje edytor przypomnienia z poziomu głównego widoku. Arkusz przypięty do sekcji
/// wewnątrz `Form` nie był prezentowany niezawodnie (leniwy kontener).
@Observable
final class ReminderPresenter {
    struct Request: Identifiable {
        let id = UUID()
        let draft: ReminderDraft
        let dueDate: LocalDate?
        let existing: RemindersService.ReminderInfo?
        let onSave: (ReminderDraft, String?) -> Void
    }

    var request: Request?
    /// Zwiększane po zapisie — sekcje odświeżają stan przypomnienia.
    private(set) var revision = 0

    func present(_ request: Request) { self.request = request }
    func didSave() { revision += 1 }
}

/// Sekcja "Przypomnienie" w szczegółach faktury lub paczki przelewów.
struct ReminderSection: View {
    let target: ReminderTarget
    /// Domyślna treść nowego przypomnienia (wyliczana przy otwarciu arkusza).
    let makeDraft: () -> ReminderDraft
    /// Termin płatności — szybki wybór „2 dni przed terminem” / „w dniu terminu”.
    var dueDate: LocalDate?

    @Environment(AppModel.self) private var model
    @Environment(ReminderPresenter.self) private var presenter
    @State private var info: RemindersService.ReminderInfo?
    @State private var error: String?

    var body: some View {
        Section {
            if let info {
                VStack(alignment: .leading, spacing: 3) {
                    Label {
                        Text(info.title).strikethrough(info.isCompleted)
                    } icon: {
                        Image(systemName: info.isCompleted ? "checkmark.circle.fill" : "bell.fill")
                            .foregroundStyle(info.isCompleted ? .green : .orange)
                    }
                    if let due = info.due {
                        Text("\(due.formatted(date: .abbreviated, time: .shortened)) · \(info.listName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Zmień przypomnienie") { openEditor() }
                Button("Usuń przypomnienie", role: .destructive) { remove() }
            } else {
                Button { openEditor() } label: { Label("Dodaj przypomnienie", systemImage: "bell.badge") }
            }
            if model.reminders.isDenied {
                Text("Brak dostępu do Przypomnień. Włącz go w Ustawieniach iOS → KS-eFektywnie → Przypomnienia.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Przypomnienie")
        }
        .task(id: "\(target.deepLink)-\(presenter.revision)") { refresh() }
    }

    private var links: ReminderLinkRepository? { model.reminderLinks }

    private func refresh() {
        guard let identifier = try? links?.identifier(for: target) else { info = nil; return }
        info = model.reminders.info(identifier)
        if info == nil, model.reminders.hasAccess { try? links?.unlink(target) }
    }

    private func openEditor() {
        Task {
            guard await model.reminders.requestAccess() else {
                error = String(localized: "Brak dostępu do Przypomnień.")
                return
            }
            var draft = makeDraft()
            if let info {
                draft.title = info.title
                if let due = info.due {
                    draft.due = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                }
            }
            presenter.present(.init(draft: draft, dueDate: dueDate, existing: info) { draft, listID in
                save(draft, listID: listID)
            })
        }
    }

    private func save(_ draft: ReminderDraft, listID: String?) {
        do {
            let identifier = try model.reminders.save(draft, listID: listID, existing: info?.identifier)
            try links?.link(target, identifier: identifier)
            error = nil
            refresh()
            presenter.didSave()
        } catch {
            self.error = error.userMessage
        }
    }

    private func remove() {
        guard let info else { return }
        try? model.reminders.remove(info.identifier)
        try? links?.unlink(target)
        refresh()
    }
}

struct ReminderEditor: View {
    @State var draft: ReminderDraft
    let dueDate: LocalDate?
    let existing: RemindersService.ReminderInfo?
    let onSave: (ReminderDraft, String?) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var listID: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tytuł", text: $draft.title, axis: .vertical)
                    DatePicker("Kiedy", selection: $date)
                }
                Section("Szybki wybór") {
                    if let dueDate {
                        Button("2 dni przed terminem płatności") { set(ReminderSchedule.shift(dueDate, days: -2)) }
                        Button("W dniu terminu płatności") { set(dueDate) }
                    }
                    Button("Jutro rano") { set(ReminderSchedule.shift(.today(), days: 1)) }
                    Button("Za tydzień") { set(ReminderSchedule.shift(.today(), days: 7)) }
                }
                Section("Lista") {
                    Picker("Lista", selection: $listID) {
                        ForEach(model.reminders.lists, id: \.calendarIdentifier) { list in
                            Text(list.title).tag(Optional(list.calendarIdentifier))
                        }
                    }
                }
                Section("Notatka") {
                    Text(draft.notes).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? String(localized: "Nowe przypomnienie") : String(localized: "Przypomnienie"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Dodaj" : "Zapisz") {
                        draft.due = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                        onSave(draft, listID)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                date = Calendar.current.date(from: draft.due) ?? Date()
                listID = model.reminders.defaultList?.calendarIdentifier
            }
        }
    }

    /// Dzień z szybkiego wyboru o domyślnej godzinie przypomnień.
    private func set(_ day: LocalDate) {
        let target = max(day, .today())
        date = Calendar.current.date(from: ReminderSchedule.components(target)) ?? date
    }
}
