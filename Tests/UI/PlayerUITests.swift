import XCTest

final class PlayerUITests: XCTestCase {
    func testPlaybackControlsAndSettings() {
        let app = XCUIApplication()
        app.launch()
        let address = app.textFields["streamURL"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap(); address.typeText("http://127.0.0.1:8765/fixture.mp4")
        app.buttons["openStream"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let center = app.buttons["centerPlayPause"]
        XCTAssertTrue(center.waitForExistence(timeout: 20))
        let clock = app.staticTexts["playbackClock"]
        let progressed = NSPredicate(format: "label != '0:00'")
        expectation(for: progressed, evaluatedWith: clock)
        waitForExpectations(timeout: 20)
        center.tap() // keep controls visible while paused
        capture("Landscape player")
        app.buttons["Playback speed"].tap()
        app.buttons["1.5×"].tap()
        app.buttons["Anime4K"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Modus A · Balanced'")).firstMatch.tap()
        app.buttons["Fertig"].tap()
        app.buttons["Subtitle language und Stil"].tap()
        XCTAssertTrue(app.staticTexts["Harbor-Untertitelstil"].waitForExistence(timeout: 5))
        capture("Subtitle settings")
        app.buttons["Fertig"].tap()
        XCUIDevice.shared.orientation = .portrait
        capture("Portrait player")
        app.buttons["Player schließen"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 10))
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
