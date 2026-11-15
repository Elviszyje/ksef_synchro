import XCTest

/// Ekran napiwków: tytuł po polsku, a gdy App Store nie zwróci produktów — stan błędu z ponowieniem,
/// bez zapowiedzi „będzie w przyszłej wersji” (recenzja Apple odrzuca treści zastępcze).
final class TipJarUITests: XCTestCase {
    @MainActor
    func testTitleAndUnavailableState() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        let tab = app.tabBars.buttons["Ustawienia"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), app.debugDescription)
        tab.tap()
        let row = app.buttons["Napiwek dla autora"]
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Napiwek dla autora"].waitForExistence(timeout: 5), app.debugDescription)

        // Na symulatorze bez konfiguracji StoreKit produkty się nie wczytują; z nią widać napiwki.
        let retry = app.buttons["Spróbuj ponownie"]
        let firstTip = app.staticTexts["Kawa dla autora"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && !retry.exists && !firstTip.exists { usleep(300_000) }
        XCTAssertTrue(retry.exists || firstTip.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'opublikowanej w App Store'")).firstMatch.exists)
    }
}
