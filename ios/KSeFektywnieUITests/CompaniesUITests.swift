import XCTest

/// Kilka firm: przełącznik na Pulpicie, widok „Wszystkie firmy” i dane zakładek zależne od aktywnej firmy.
final class CompaniesUITests: XCTestCase {
    @MainActor
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Bez argumentu `-dashboardAllCompanies`: wartość z argumentów uruchomienia przesłania zapis
        // ustawienia, więc wybór „Wszystkie firmy” w menu nie miałby skutku.
        app.launchArguments = ["-demo", "-demo-second", "YES", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()
        return app
    }

    @MainActor
    func testSwitchCompanyChangesInvoices() {
        let app = launch()
        let switcher = app.buttons["company-switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 15), app.debugDescription)
        switcher.tap()
        let second = app.buttons["Anna Nowak Projektowanie"]
        XCTAssertTrue(second.waitForExistence(timeout: 5), app.debugDescription)
        second.tap()

        app.tabBars.buttons["Faktury"].tap()
        // Faktura drugiej firmy jest na liście, faktura pierwszej zniknęła.
        XCTAssertTrue(app.staticTexts["FV/2026/0101"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["FV/2026/0001"].exists)
    }

    /// Przełącznik w pasku nawigacji zakładek Faktury, Przelewy i Wyciągi.
    @MainActor
    func testSwitchCompanyFromInvoicesTab() {
        let app = launch()
        app.tabBars.buttons["Faktury"].tap()
        XCTAssertTrue(app.staticTexts["FV/2026/0001"].waitForExistence(timeout: 15), app.debugDescription)
        let switcher = app.buttons["company-switcher-toolbar"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), app.debugDescription)
        switcher.tap()
        let second = app.buttons["Anna Nowak Projektowanie"]
        XCTAssertTrue(second.waitForExistence(timeout: 5), app.debugDescription)
        second.tap()
        XCTAssertTrue(app.staticTexts["FV/2026/0101"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["FV/2026/0001"].exists)

        for tab in ["Przelewy", "Wyciągi"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.buttons["company-switcher-toolbar"].waitForExistence(timeout: 5), "\(tab): \(app.debugDescription)")
        }
    }

    @MainActor
    func testAllCompaniesViewListsEveryCompany() {
        let app = launch()
        let switcher = app.buttons["company-switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 15), app.debugDescription)
        switcher.tap()
        let all = app.buttons["Wszystkie firmy"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), app.debugDescription)
        all.tap()

        // Karta „Do zapłaty” rozbija kwotę na firmy; dotknięcie otwiera Przelewy tej firmy.
        let secondRow = app.buttons["payable-company-2222222222"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["payable-company-1111111111"].exists)
        secondRow.tap()
        XCTAssertTrue(app.navigationBars["Przelewy"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["FV/2026/0102"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testAddCompanyFormIsReachableFromSettings() {
        let app = launch()
        app.tabBars.buttons["Ustawienia"].tap()
        let add = app.buttons["add-company"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), app.debugDescription)
        add.tap()
        XCTAssertTrue(app.navigationBars["Nowa firma"].waitForExistence(timeout: 5), app.debugDescription)
        // Bez NIP-u i nazwy nie da się dodać firmy.
        XCTAssertFalse(app.navigationBars.buttons["Dodaj"].isEnabled)
        app.navigationBars.buttons["Anuluj"].tap()
    }

    /// Dodanie trzeciej firmy: staje się aktywna, a przycisk dodawania znika (limit 3 firm).
    @MainActor
    func testAddThirdCompanyReachesLimit() {
        let app = launch()
        app.tabBars.buttons["Ustawienia"].tap()
        let add = app.buttons["add-company"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), app.debugDescription)
        add.tap()
        // Najpierw nazwa: przy wypełnionej nazwie wpisanie NIP-u nie odpytuje Białej Listy.
        let name = app.textFields["Nazwa firmy"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        name.tap()
        name.typeText("Trzecia Firma Testowa")
        let nip = app.textFields["NIP"]
        nip.tap()
        nip.typeText("3333333333")
        let save = app.navigationBars.buttons["Dodaj"]
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        save.tap()

        XCTAssertTrue(app.staticTexts["Trzecia Firma Testowa"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["add-company"].exists)
        // Nowa firma jest aktywna: zakładka Faktury jest pusta.
        app.tabBars.buttons["Faktury"].tap()
        XCTAssertTrue(app.staticTexts["Brak faktur"].waitForExistence(timeout: 5), app.debugDescription)
    }
}
