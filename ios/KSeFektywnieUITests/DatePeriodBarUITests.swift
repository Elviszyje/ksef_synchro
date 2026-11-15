import XCTest

/// Pasek okresu nad listą faktur: segmenty mieszczą się na ekranie, a własny zakres dat
/// pojawia się pod paskiem i da się go ponownie otworzyć (dane demo).
final class DatePeriodBarUITests: XCTestCase {
    @MainActor
    func testSegmentsFitAndCustomRangeIsEditable() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        let segments = app.segmentedControls.firstMatch
        XCTAssertTrue(segments.waitForExistence(timeout: 15), app.debugDescription)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(segments.buttons.count, 4)
        for index in 0..<4 {
            let frame = segments.buttons.element(boundBy: index).frame
            XCTAssertTrue(window.contains(frame), "Segment \(index) wychodzi poza ekran: \(frame)")
        }

        segments.buttons["Ten miesiąc"].tap()
        XCTAssertTrue(segments.buttons["Ten miesiąc"].isSelected)

        segments.buttons.element(boundBy: 3).tap()
        let apply = app.buttons["Zastosuj"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5), app.debugDescription)
        apply.tap()
        let range = app.buttons["period-custom"]
        XCTAssertTrue(range.waitForExistence(timeout: 5), app.debugDescription)

        range.tap()
        XCTAssertTrue(app.buttons["Anuluj"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Anuluj"].tap()
        XCTAssertTrue(range.waitForExistence(timeout: 5))

        segments.buttons["Wszystkie"].tap()
        XCTAssertFalse(range.waitForExistence(timeout: 2))
    }
}
