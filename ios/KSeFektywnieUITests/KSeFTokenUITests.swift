import XCTest

/// Wskaźnik tokenu w Ustawieniach odświeża się po zapisie i usunięciu tokenu (dane demo).
/// Pęk kluczy nie jest obserwowalny, więc bez jawnego odświeżenia wiersz pokazywał stary stan.
final class KSeFTokenUITests: XCTestCase {
    @MainActor
    func testSettingsRowFollowsTokenState() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        func element(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        let back = app.navigationBars.buttons.firstMatch

        let tab = app.tabBars.buttons["Ustawienia"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), app.debugDescription)
        tab.tap()
        XCTAssertTrue(element("Nie skonfigurowano").waitForExistence(timeout: 10), app.debugDescription)

        element("Połączenie z KSeF").tap()
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        field.tap()
        field.typeText("token-testowy")
        app.buttons["Zapisz token"].tap()
        XCTAssertTrue(app.buttons["Usuń token"].waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
        XCTAssertTrue(element("Token zapisany").waitForExistence(timeout: 5), app.debugDescription)

        element("Połączenie z KSeF").tap()
        app.buttons["Usuń token"].tap()
        back.tap()
        XCTAssertTrue(element("Nie skonfigurowano").waitForExistence(timeout: 5), app.debugDescription)
    }
}
