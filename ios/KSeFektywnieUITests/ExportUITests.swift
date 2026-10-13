import XCTest

/// Menu eksportu listy faktur (Excel i PDF) otwiera arkusz udostępniania z plikiem.
final class ExportUITests: XCTestCase {
    @MainActor
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["FV/2026/0001"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func export(_ option: String, expecting ext: String) {
        let app = launch()
        app.buttons["export-menu"].firstMatch.tap()
        let button = app.buttons[option]
        XCTAssertTrue(button.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.buttons["Excel (.xlsx)"].exists && app.buttons["PDF"].exists)
        button.tap()
        // Nazwa pliku w nagłówku arkusza udostępniania.
        let caption = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ENDSWITH[c] %@ OR identifier ENDSWITH[c] %@", ".\(ext)", ".\(ext)")).firstMatch
        let shown = caption.waitForExistence(timeout: 10)
        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot()))
        XCTAssertTrue(shown, "Brak arkusza udostępniania z plikiem .\(ext)\n\(app.debugDescription)")
    }

    @MainActor
    func testExportExcel() { export("Excel (.xlsx)", expecting: "xlsx") }

    @MainActor
    func testExportPDF() { export("PDF", expecting: "pdf") }
}
