import Foundation
import GRDB
import Domain
import Persistence

/// Dane przykładowe: tryb "Wypróbuj bez KSeF" i konto dla recenzentów App Store.
/// NIP-y i rachunki są fikcyjne (poprawne sumy kontrolne, nie należą do realnych firm).
public enum DemoData {
    public static let companyNIP = "1111111111"

    struct Seller {
        let name, nip, address, account: String
    }

    static let sellers = [
        Seller(name: "Hurtownia Papiernicza Ołówek Sp. z o.o.", nip: "6260181591", address: "ul. Przykładowa 1, 00-001 Warszawa", account: "28109000003231948757491186"),
        Seller(name: "Serwis IT Bajt S.A.", nip: "1830166138", address: "ul. Krzemowa 12, 30-001 Kraków", account: "18114000002527601895559797"),
        Seller(name: "Energia Demo Sp. z o.o.", nip: "2860913907", address: "ul. Prądowa 5, 80-001 Gdańsk", account: "19102000001147104974650752"),
        Seller(name: "Kancelaria Rachunkowa Saldo", nip: "7030824620", address: "ul. Bilansowa 3, 90-001 Łódź", account: "87249000009170342366712768"),
        Seller(name: "Stal i Pręt Budmax Demo S.A.", nip: "9194821999", address: "ul. Hutnicza 8, 40-001 Katowice", account: "02168000004268465632122330"),
        Seller(name: "Telekom Przykład Sp. z o.o.", nip: "8865797544", address: "ul. Światłowodowa 2, 50-001 Wrocław", account: "20105000007924402685995289"),
    ]

    /// Tworzy firmę demo z fakturami w różnych statusach. Terminy liczone od `today`.
    @discardableResult
    public static func seed(db: AppDatabase, device: String, today: LocalDate = .today(), now: Date = Date()) throws -> Company {
        let company = Company(nip: companyNIP, name: "Firma Demo Sp. z o.o.", address: "ul. Testowa 10, 00-950 Warszawa",
                              ksefEnvironment: .test, updatedByDevice: device)
        let account = CompanyBankAccount(companyID: company.id, accountNumber: "61109010140000071219812874", label: "Konto firmowe", isDefault: true)
        try db.writer.write { db in
            try company.insert(db)
            try account.insert(db)
        }

        func day(_ offset: Int) -> LocalDate { LocalDate(Calendar.current.date(byAdding: .day, value: offset, to: today.date())!) }
        func invoice(_ i: Int, seller: Seller, net netText: String, rate: Decimal = 23, issued: Int, due: Int?, status: InvoiceStatus,
                     split: Bool = false, type: String = "VAT", item: String) -> Invoice {
            // Kwoty jako tekst: literał Decimal przechodzi przez Double i traci precyzję (1204.88 → 1204.8799…).
            let net = DecimalText.parse(netText)!
            let vat = (net * rate / 100).rounded(scale: 2)
            let number = "FV/\(today.year)/\(String(format: "%04d", i))"
            let ref = "\(seller.nip)-\(day(issued).compact)-DEMO\(String(format: "%06d", i))"
            return Invoice(companyID: company.id, ksefReferenceNumber: ref, invoiceNumber: number,
                           sellerName: seller.name, sellerNIP: seller.nip, sellerAddress: seller.address, buyerNIP: companyNIP,
                           amountNet: net, amountVAT: vat, amountGross: net + vat, isSplitPayment: split,
                           issueDate: day(issued), paymentDueDate: due.map(day), bankAccountNumber: seller.account,
                           paymentTitle: "Faktura \(number)", paymentForm: "przelew", status: status, invoiceType: type,
                           description: item, rawXML: xml(number: number, seller: seller, issued: day(issued), due: due.map(day),
                                                          net: net, vat: vat, item: item, split: split),
                           syncedAt: now, updatedAt: now, updatedByDevice: device)
        }

        let invoices = [
            invoice(1, seller: sellers[0], net: "812.50", issued: -2, due: 12, status: .new, item: "Papier A4, segregatory, tonery"),
            invoice(2, seller: sellers[1], net: "3500", issued: -10, due: 4, status: .accepted, item: "Abonament serwisowy — październik"),
            invoice(3, seller: sellers[2], net: "1204.88", issued: -20, due: -3, status: .new, item: "Energia elektryczna — wrzesień"),
            invoice(4, seller: sellers[3], net: "1800", issued: -15, due: 0, status: .disputed, item: "Prowadzenie księgowości"),
            invoice(5, seller: sellers[4], net: "20000", issued: -6, due: 24, status: .accepted, split: true, item: "Pręt zbrojeniowy fi 12, 5 t"),
            invoice(6, seller: sellers[5], net: "149.59", issued: -25, due: -11, status: .sentForPayment, item: "Internet światłowodowy"),
            invoice(7, seller: sellers[5], net: "149.59", issued: -55, due: -41, status: .paid, item: "Internet światłowodowy"),
            invoice(8, seller: sellers[0], net: "-100", issued: -1, due: nil, status: .new, type: "KOR", item: "Korekta — zwrot tonera"),
        ]
        try InvoiceRepository(db: db, companyID: company.id, device: device).upsertFromKSeF(invoices, now: now)
        try seedSales(company: company, account: account, db: db, device: device, today: today, now: now)
        return company
    }

    /// Szkic faktury sprzedażowej ze stawką ZW i katalog pozycji z kilku wcześniejszych faktur.
    static func seedSales(company: Company, account: CompanyBankAccount, db: AppDatabase, device: String, today: LocalDate, now: Date) throws {
        let sales = SalesRepository(db: db, companyID: company.id, device: device)
        let due = LocalDate(Calendar.current.date(byAdding: .day, value: 14, to: today.date())!)
        func draft(_ n: Int, buyer: Seller, items: [OutgoingInvoiceItem], basis: String = "") -> OutgoingInvoice {
            OutgoingInvoice(companyID: company.id, invoiceNumber: "FV/\(today.year)/\(String(format: "%04d", n))",
                            issueDate: today, paymentDueDate: due, bankAccountNumber: account.accountNumber,
                            buyerNIP: buyer.nip, buyerName: buyer.name, buyerAddress: buyer.address,
                            exemptionBasis: basis, environment: .test, items: items)
        }
        let consulting = OutgoingInvoiceItem(name: "Konsultacje IT", unit: "h", quantity: 8, unitPriceNet: 200)
        let training = OutgoingInvoiceItem(name: "Szkolenie BHP", unit: "os.", quantity: 3, unitPriceNet: 350, vatRate: .exempt)
        let hosting = OutgoingInvoiceItem(name: "Hosting aplikacji — miesiąc", unit: "mies.", quantity: 1, unitPriceNet: 99)
        try sales.saveDraft(draft(1, buyer: sellers[1], items: [consulting, hosting]), saveBuyer: true, now: now)
        try sales.saveDraft(draft(2, buyer: sellers[3], items: [training, consulting],
                                  basis: "art. 43 ust. 1 pkt 29 lit. a ustawy o VAT"), saveBuyer: true, now: now)
    }

    /// Minimalny XML FA(3), żeby w szczególe faktury było widać pozycje.
    static func xml(number: String, seller: Seller, issued: LocalDate, due: LocalDate?, net: Decimal, vat: Decimal, item: String, split: Bool) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let n = DecimalText.string(net), v = DecimalText.string(vat), g = DecimalText.string(net + vat)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
          <Podmiot1><DaneIdentyfikacyjne><NIP>\(seller.nip)</NIP><Nazwa>\(esc(seller.name))</Nazwa></DaneIdentyfikacyjne></Podmiot1>
          <Podmiot2><DaneIdentyfikacyjne><NIP>\(companyNIP)</NIP></DaneIdentyfikacyjne></Podmiot2>
          <Fa><KodWaluty>PLN</KodWaluty><P_1>\(issued.iso)</P_1><P_2>\(number)</P_2>
            <P_13_1>\(n)</P_13_1><P_14_1>\(v)</P_14_1><P_15>\(g)</P_15>
            <FaWiersz><NrWierszaFa>1</NrWierszaFa><P_7>\(esc(item))</P_7><P_8A>szt.</P_8A><P_8B>1</P_8B><P_9A>\(n)</P_9A><P_11>\(n)</P_11><P_12>23</P_12></FaWiersz>
            <Platnosc>\(due.map { "<TerminPlatnosci><Termin>\($0.iso)</Termin></TerminPlatnosci>" } ?? "")<FormaPlatnosci>6</FormaPlatnosci>\(split ? "<MechanizmPodzielonejPlatnosci>T</MechanizmPodzielonejPlatnosci>" : "")<RachunekBankowy><NrRB>\(seller.account)</NrRB></RachunekBankowy></Platnosc>
          </Fa>
        </Faktura>
        """
    }
}
