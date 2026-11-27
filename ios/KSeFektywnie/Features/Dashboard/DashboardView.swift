import SwiftUI
import GRDB
import Domain
import Persistence

/// Pulpit: koszty wybranego miesiąca, VAT z faktur, kwota do zapłaty i najbliższe terminy.
/// Wszystko liczone z faktur kosztowych w PLN (inne waluty wymagałyby kursów).
///
/// Przełącznik firmy w pasku (`CompanySwitcherMenu`, ten sam co w innych zakładkach) ma tu dodatkowo
/// „Wszystkie firmy” — wtedy Pulpit sumuje dane ponad firmami, a pozostałe zakładki dalej pracują na aktywnej.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Faktury kosztowe wszystkich firm; `invoices` zawęża je do wybranego zakresu.
    @State private var allInvoices: [Invoice] = []
    @AppStorage("dashboardAllCompanies") private var wantsAllCompanies = false
    @State private var month = LocalDate.today().firstOfMonth
    @State private var path: [UUID] = []
    @State private var showSummary = DebugLaunch.openDashboard
    let openPayments: () -> Void
    let openInvoices: () -> Void

    private let today = LocalDate.today()

    /// Widok łączny ma sens dopiero przy co najmniej dwóch firmach.
    private var showsAllCompanies: Bool { wantsAllCompanies && model.companies.count > 1 }

    private var invoices: [Invoice] {
        showsAllCompanies ? allInvoices : allInvoices.filter { $0.companyID == model.company?.id }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        monthSwitcher
                    }
                    if model.isDemo && !DebugLaunch.storeShots {
                        banner(Text("Tryb demo — dane przykładowe"), systemImage: "theatermasks")
                    }
                    if let message = model.syncBanner {
                        banner(Text(message), systemImage: "arrow.triangle.2.circlepath")
                    }
                    costCard
                    payableCard
                    upcomingSection
                    sellersSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .refreshable { await model.sync(allCompanies: showsAllCompanies) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CompanySwitcherMenu(allCompanies: $wantsAllCompanies, accessibilityID: "company-switcher")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .animation(.snappy, value: model.syncBanner)
            .navigationDestination(for: UUID.self) { InvoiceDetailView(invoiceID: $0) }
            .navigationDestination(isPresented: $showSummary) { CostDashboardView() }
            .task { await observe() }
        }
    }

    // MARK: - Sekcje

    /// Wybór miesiąca: poprzedni / następny w obrębie ostatnich 12 miesięcy.
    private var monthSwitcher: some View {
        HStack(spacing: 2) {
            Button { month = month.addingMonths(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 36)
            }
            .disabled(month <= oldestMonth)
            .accessibilityLabel(Text("Poprzedni miesiąc"))
            Text(monthTitle)
                .font(.grotesk(13, .medium, relativeTo: .footnote))
                .frame(minWidth: 74)
            Button { month = month.addingMonths(1) } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 36)
            }
            .disabled(month >= today.firstOfMonth)
            .accessibilityLabel(Text("Następny miesiąc"))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.appInk)
        .padding(.horizontal, 4)
        .background(Color.appSurface, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.appLine))
        .sensoryFeedback(.selection, trigger: month)
    }

    private var costCard: some View {
        let stats = monthStats(month)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Koszty: \(monthName)")
                Spacer()
                Text("\(stats.count) faktur")
            }
            .font(.grotesk(13, .medium, relativeTo: .footnote))
            .foregroundStyle(Color.appMuted)
            HeroAmount(amount: stats.gross)
            monthBars
            Divider().overlay(Color.appLine)
            HStack(alignment: .firstTextBaseline) {
                Text("VAT z faktur kosztowych")
                    .font(.grotesk(14, relativeTo: .subheadline))
                    .foregroundStyle(Color.appMuted)
                Spacer()
                Text(stats.vat.money()).font(.grotesk(15, .medium, relativeTo: .subheadline)).monospacedDigit()
            }
            if otherCurrencyCount > 0 {
                Text("Faktury w innych walutach (\(otherCurrencyCount)) nie są wliczane do sum.")
                    .font(.appCaption).foregroundStyle(Color.appMuted)
            }
        }
        .appCard(padding: 20)
    }

    /// Słupki 12 miesięcy; dotknięcie wybiera miesiąc.
    private var monthBars: some View {
        let months = windowMonths
        let values = months.map { monthStats($0).gross }
        let peak = max(values.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(months.enumerated()), id: \.element) { index, item in
                let share = CGFloat(truncating: (max(values[index], 0) / peak) as NSDecimalNumber)
                Button { month = item } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(item == month ? Color.appPrimaryFill : Color.appLine)
                        .frame(height: max(4, 56 * share))
                        .frame(maxWidth: .infinity, maxHeight: 56, alignment: .bottom)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("month-bar")
                .accessibilityLabel(Text(item.date().formatted(.dateTime.month(.wide).year())))
                .accessibilityValue(Text(values[index].money()))
                .accessibilityAddTraits(item == month ? .isSelected : [])
            }
        }
        .frame(height: 56)
        .animation(.snappy, value: month)
    }

    private var payableCard: some View {
        let payable = invoices.filter { $0.currency == "PLN" && !$0.isCorrection && ($0.status == .new || $0.status == .accepted) }
        let total = payable.reduce(Decimal(0)) { $0 + $1.amountGross }
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Do zapłaty · \(payable.count) faktur")
                        .font(.grotesk(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.appOnGraphiteMuted)
                    HeroAmount(amount: total, size: 24, onGraphite: true)
                }
                Spacer(minLength: 8)
                if !showsAllCompanies {
                    Button(action: openPayments) {
                        HStack(spacing: 6) {
                            Text("Przelewy")
                            Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                        }
                    }
                    .buttonStyle(.appMint)
                }
            }
            // Widok łączny: kwota każdej firmy osobno; dotknięcie otwiera jej Przelewy.
            if showsAllCompanies {
                VStack(spacing: 0) {
                    ForEach(model.companies) { company in
                        let amount = payable.filter { $0.companyID == company.id }.reduce(Decimal(0)) { $0 + $1.amountGross }
                        Divider().overlay(Color.appOnGraphiteMuted.opacity(0.3))
                        Button {
                            model.activate(company.id)
                            openPayments()
                        } label: {
                            HStack(spacing: 8) {
                                Text(company.name)
                                    .font(.grotesk(14, .medium, relativeTo: .subheadline))
                                    .foregroundStyle(Color.appOnGraphite)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(amount.money())
                                    .font(.grotesk(14, .medium, relativeTo: .subheadline))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.appOnGraphite)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.appMint)
                            }
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("payable-company-\(company.nip)")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, showsAllCompanies ? 4 : 16)
        .background(Color.appFeatureCard, in: .rect(cornerRadius: 22))
    }

    @ViewBuilder
    private var upcomingSection: some View {
        let upcoming = invoices
            .filter { !$0.isCorrection && ($0.status == .new || $0.status == .accepted) && $0.paymentDueDate != nil }
            .sorted { ($0.paymentDueDate!, $0.invoiceNumber) < ($1.paymentDueDate!, $1.invoiceNumber) }
        sectionHeader("Najbliższe terminy") {
            if upcoming.count > 3 && !showsAllCompanies {
                Button(action: openInvoices) { Text("Wszystkie (\(upcoming.count))") }
            }
        }
        if upcoming.isEmpty {
            Text("Brak nieopłaconych faktur z terminem.")
                .font(.appSubheadline).foregroundStyle(Color.appMuted)
                .appCard()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(upcoming.prefix(showsAllCompanies ? 5 : 3).enumerated()), id: \.element.id) { index, invoice in
                    if index > 0 { Divider().overlay(Color.appLine) }
                    // Szczegóły faktury czytają dane aktywnej firmy, więc w widoku łącznym
                    // dotknięcie najpierw aktywuje firmę tej faktury.
                    Button {
                        model.activate(invoice.companyID)
                        path.append(invoice.id)
                    } label: {
                        InvoiceRow(invoice: invoice, today: today,
                                   companyName: showsAllCompanies ? companyName(invoice.companyID) : nil)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var sellersSection: some View {
        let sellers = topSellers(month)
        sectionHeader("Najwięksi dostawcy") {
            Button { showSummary = true } label: { Text("12 miesięcy") }
        }
        if sellers.isEmpty {
            Text("W tym miesiącu nie ma jeszcze faktur kosztowych.")
                .font(.appSubheadline).foregroundStyle(Color.appMuted)
                .appCard()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sellers.enumerated()), id: \.element.id) { index, seller in
                    if index > 0 { Divider().overlay(Color.appLine) }
                    Button { open(seller) } label: {
                        HStack(spacing: 12) {
                            Text(seller.name)
                                .font(.grotesk(15, .medium, relativeTo: .subheadline))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(seller.gross.money())
                                .font(.grotesk(15, .medium, relativeTo: .subheadline))
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.appMuted)
                        }
                        .foregroundStyle(Color.appInk)
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("top-seller-\(index)")
                }
            }
            .padding(.horizontal, 18)
            .background(Color.appSurface, in: .rect(cornerRadius: 22))
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.grotesk(15, .bold, relativeTo: .headline))
            Spacer()
            trailing().font(.grotesk(13, .medium, relativeTo: .footnote))
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
    }

    private func banner(_ text: Text, systemImage: String) -> some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .font(.appFootnote)
            .foregroundStyle(Color.appMuted)
            .appCard(padding: 12, radius: 16)
    }

    // MARK: - Dane

    private var monthTitle: String {
        month.date().formatted(month.year == today.year ? .dateTime.month(.wide) : .dateTime.month(.abbreviated).year())
            .capitalizedFirst
    }

    /// Nazwa miesiąca do zdania „Koszty: listopad”.
    private var monthName: String {
        month.date().formatted(month.year == today.year ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    private var oldestMonth: LocalDate { today.firstOfMonth.addingMonths(-11) }

    private var windowMonths: [LocalDate] { (0..<12).map { oldestMonth.addingMonths($0) } }

    private var otherCurrencyCount: Int { invoices.filter { $0.currency != "PLN" }.count }

    private func inMonth(_ invoice: Invoice, _ month: LocalDate) -> Bool {
        invoice.currency == "PLN" && invoice.issueDate.year == month.year && invoice.issueDate.month == month.month
    }

    private func monthStats(_ month: LocalDate) -> (gross: Decimal, vat: Decimal, count: Int) {
        let items = invoices.filter { inMonth($0, month) }
        return (items.reduce(0) { $0 + $1.amountGross }, items.reduce(0) { $0 + $1.amountVAT }, items.count)
    }

    private struct SellerTotal: Identifiable {
        let id: String
        let name: String
        let nip: String
        /// Firma, której fakturę od dostawcy spotkano pierwszą (widok łączny przełącza się na nią).
        let companyID: UUID
        var gross: Decimal
    }

    /// Lista faktur kosztowych zawężona do dostawcy (po NIP-ie, a bez NIP-u po nazwie).
    private func open(_ seller: SellerTotal) {
        model.invoiceSearchRequest = seller.nip.isEmpty ? seller.name : seller.nip
        if seller.companyID != model.company?.id { model.activate(seller.companyID) }
        openInvoices()
    }

    private func topSellers(_ month: LocalDate) -> [SellerTotal] {
        var sellers: [String: SellerTotal] = [:]
        for invoice in invoices where inMonth(invoice, month) {
            var seller = sellers[invoice.sellerNIP]
                ?? SellerTotal(id: invoice.sellerNIP, name: invoice.sellerName, nip: invoice.sellerNIP,
                               companyID: invoice.companyID, gross: 0)
            seller.gross += invoice.amountGross
            sellers[invoice.sellerNIP] = seller
        }
        return Array(sellers.values.sorted { ($0.gross, $1.name) > ($1.gross, $0.name) }.prefix(3))
    }

    private func companyName(_ id: UUID) -> String? {
        model.companies.first { $0.id == id }?.name
    }

    /// Jedna obserwacja faktur wszystkich firm — przełączanie zakresu nie wymaga jej ponawiania.
    private func observe() async {
        let observation = ValueObservation.tracking { db in
            try Invoice.order(Column("issueDate").desc, Column("syncedAt").desc).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: model.database.reader) {
                allInvoices = value
            }
        } catch {}
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
