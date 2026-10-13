import XCTest

/// Prawdziwe gesty na liście faktur (dane demo).
final class InvoiceSwipeUITests: XCTestCase {
    @MainActor
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()
        return app
    }

    @MainActor
    func row(_ number: String, in app: XCUIApplication) -> XCUIElement {
        let text = app.staticTexts[number]
        XCTAssertTrue(text.waitForExistence(timeout: 10), "Brak faktury \(number) na liście")
        return text
    }

    @MainActor
    func testSwipeRightShowsApproveAction() {
        let app = launch()
        row("FV/2026/0001", in: app).swipeRight()
        XCTAssertTrue(app.buttons["Do zapłaty"].waitForExistence(timeout: 3), app.debugDescription)
    }

    @MainActor
    func testSwipeLeftShowsDisputeAction() {
        let app = launch()
        row("FV/2026/0001", in: app).swipeLeft()
        XCTAssertTrue(app.buttons["Sporna"].waitForExistence(timeout: 3), app.debugDescription)
    }
}
