import XCTest

/// Wizualizacja PDF faktur (dane demo): koszt z udostępnianiem, szkic sprzedaży, nowy szablon.
final class InvoiceVisualizationUITests: XCTestCase {
    @MainActor
    func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + arguments + ["-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()
        return app
    }

    @MainActor
    func testCostInvoicePDFAndShare() {
        let app = launch(["-open-invoice", "FV/2026/0001"])
        XCTAssertTrue(app.staticTexts["Status"].waitForExistence(timeout: 10))
        let link = app.buttons["invoice-visualization"]
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any)["invoice-pdf"].waitForExistence(timeout: 10), app.debugDescription)
        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot()))

        app.buttons["share-pdf"].tap()
        let caption = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ENDSWITH[c] '.pdf' OR identifier ENDSWITH[c] '.pdf'")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 10), "Brak arkusza udostępniania z plikiem .pdf\n\(app.debugDescription)")
    }

    @MainActor
    func testSalesDraftPDF() {
        let app = launch(["-tab", "sales", "-open-sale", "1"])
        let preview = app.buttons["draft-pdf"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), app.debugDescription)
        preview.tap()
        XCTAssertTrue(app.descendants(matching: .any)["invoice-pdf"].waitForExistence(timeout: 10), app.debugDescription)
        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot()))
        XCTAssertTrue(app.buttons["share-pdf"].exists)
    }

    @MainActor
    func testCreateTemplate() {
        let app = launch(["-tab", "settings"])
        let templates = app.buttons["Szablony faktur"]
        XCTAssertTrue(templates.waitForExistence(timeout: 10), app.debugDescription)
        templates.tap()
        XCTAssertTrue(app.staticTexts["Standardowy"].waitForExistence(timeout: 5), app.debugDescription)

        app.navigationBars.buttons["Nowy szablon"].tap()
        let name = app.textFields["Nazwa szablonu"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        // Podgląd jest pierwszym wierszem; po pojawieniu się klawiatury lista może go zwolnić.
        XCTAssertTrue(app.descendants(matching: .any)["template-preview"].waitForExistence(timeout: 5), app.debugDescription)
        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot()))
        name.tap()
        name.typeText(" EN")
        app.buttons["Nowoczesny"].tap()
        app.navigationBars.buttons["Zapisz"].tap()

        XCTAssertTrue(app.staticTexts["Nowy szablon EN"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Domyślny"].exists)
        XCTAssertFalse(app.staticTexts["Standardowy"].exists)
    }
}
