import XCTest

/// Dodanie przypomnienia do faktury (dane demo). Okno zgody na Przypomnienia obsługiwane
/// bezpośrednio przez SpringBoard (monitor przerwań zapętla się na tym oknie w iOS 26).
final class RemindersUITests: XCTestCase {
    @MainActor
    func testAddReminderToInvoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-open-invoice", "FV/2026/0001", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        let add = app.buttons["Dodaj przypomnienie"]
        XCTAssertTrue(app.staticTexts["Status"].waitForExistence(timeout: 10))
        for _ in 0..<6 where !add.isHittable { app.swipeUp() }
        add.tap()
        // Zgoda na dostęp do Przypomnień (okno systemowe przy pierwszym użyciu).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Allow' OR label BEGINSWITH[c] 'Zezwól'")).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        let save = app.navigationBars.buttons["Dodaj"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.textViews.firstMatch.exists || app.textFields.firstMatch.exists)
        save.tap()

        XCTAssertTrue(app.buttons["Zmień przypomnienie"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Usuń przypomnienie"].exists)
    }
}

/// Link z przypomnienia (`ksefektywnie://invoice/<id>`) otwiera szczegóły faktury.
final class DeepLinkUITests: XCTestCase {
    @MainActor
    func testInvoiceLinkOpensDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'invoice-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let id = String(row.identifier.dropFirst("invoice-".count))
        let number = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'FV/'")).firstMatch.label

        XCUIDevice.shared.system.open(URL(string: "ksefektywnie://invoice/\(id)")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.buttons.matching(NSPredicate(format: "label IN {'Open', 'Otwórz'}")).firstMatch
        if open.waitForExistence(timeout: 3) { open.tap() }

        XCTAssertTrue(app.navigationBars[number].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Status"].exists)
    }
}
