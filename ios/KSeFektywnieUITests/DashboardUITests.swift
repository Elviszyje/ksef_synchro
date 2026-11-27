import XCTest

/// Pulpit: wykres miesięcy i lista największych dostawców.
final class DashboardUITests: XCTestCase {
    @MainActor
    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"] + extra
        app.launch()
        return app
    }

    /// Dotknięcie każdego słupka wybiera miesiąc i nie zamyka aplikacji.
    @MainActor
    func testTappingChartBarsSelectsMonth() {
        let app = launch()
        let bars = app.buttons.matching(identifier: "month-bar")
        XCTAssertTrue(bars.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(bars.count, 12)
        for index in 0..<bars.count {
            bars.element(boundBy: index).tap()
            XCTAssertEqual(app.state, .runningForeground, "słupek \(index)")
        }
        XCTAssertTrue(app.staticTexts["Najwięksi dostawcy"].exists, app.debugDescription)
    }

    /// Dotknięcie dostawcy otwiera Faktury kosztowe z wyszukiwaniem po jego NIP-ie.
    @MainActor
    func testTopSellerOpensFilteredInvoices() {
        let app = launch()
        let seller = app.buttons["top-seller-0"]
        for _ in 0..<4 where !seller.isHittable { app.swipeUp() }
        XCTAssertTrue(seller.waitForExistence(timeout: 15), app.debugDescription)
        seller.tap()

        XCTAssertTrue(app.navigationBars["Faktury"].waitForExistence(timeout: 5), app.debugDescription)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        let term = search.value as? String ?? ""
        XCTAssertTrue(term.count == 10 && term.allSatisfy(\.isNumber), "wyszukiwanie: \(term)")
    }
}
