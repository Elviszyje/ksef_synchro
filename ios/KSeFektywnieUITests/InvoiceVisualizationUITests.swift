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

    /// Podgląd PDF faktury sprzedażowej prosto z listy (menu kontekstowe).
    @MainActor
    func testSalesPDFFromList() {
        let app = launch(["-tab", "sales"])
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'FV/2026/0001'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.press(forDuration: 1.0)
        let preview = app.buttons["Podgląd PDF"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
        preview.tap()
        XCTAssertTrue(app.descendants(matching: .any)["invoice-pdf"].waitForExistence(timeout: 10), app.debugDescription)
        snapshot("sales-list-pdf")
        XCTAssertTrue(app.buttons["share-pdf"].exists)
    }

    /// Edytor układu: przeciągnięcie sekcji płatności nad strony faktury i kodu QR na lewą stronę, zapis.
    @MainActor
    func testTemplateLayoutDrag() {
        let app = launch(["-tab", "settings"])
        let templates = app.buttons["Szablony faktur"]
        XCTAssertTrue(templates.waitForExistence(timeout: 10), app.debugDescription)
        templates.tap()
        app.staticTexts["Standardowy"].tap()
        let layoutLink = app.buttons["template-layout"]
        XCTAssertTrue(layoutLink.waitForExistence(timeout: 5), app.debugDescription)
        layoutLink.tap()

        let parties = app.descendants(matching: .any)["layout-section-parties"]
        let payment = app.descendants(matching: .any)["layout-section-payment"]
        XCTAssertTrue(payment.waitForExistence(timeout: 10), app.debugDescription)
        snapshot("layout-1-start")
        XCTAssertGreaterThan(payment.frame.minY, parties.frame.minY)

        // Przytrzymanie i przeciągnięcie sekcji na miejsce pierwszej.
        let from = payment.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let to = parties.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2))
        from.press(forDuration: 0.8, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertLessThan(payment.frame.minY, parties.frame.minY, "Sekcja płatności powinna być nad stronami faktury")

        // Kod QR na lewą stronę.
        let qr = app.descendants(matching: .any)["layout-qr"]
        XCTAssertTrue(qr.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(qr.value as? String, "Po prawej")
        let qrCenter = qr.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        qrCenter.press(forDuration: 0.05, thenDragTo: qrCenter.withOffset(CGVector(dx: -250, dy: 0)))
        sleep(1)
        XCTAssertEqual(app.descendants(matching: .any)["layout-qr"].value as? String, "Po lewej")
        snapshot("layout-2-moved")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons["Zapisz"].tap()
        XCTAssertTrue(app.staticTexts["Domyślny"].waitForExistence(timeout: 5), app.debugDescription)
        app.staticTexts["Standardowy"].firstMatch.tap()
        app.buttons["template-layout"].tap()
        XCTAssertTrue(payment.waitForExistence(timeout: 10))
        XCTAssertLessThan(payment.frame.minY, parties.frame.minY, "Kolejność sekcji powinna się zapisać")
        snapshot("layout-3-saved")
    }

    /// Zrzut jako załącznik testu; z `-UITEST_SHOTS <katalog>` także do pliku (podgląd poza Xcode).
    @MainActor
    func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["UITEST_SHOTS"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
