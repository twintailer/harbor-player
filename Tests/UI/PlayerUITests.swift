import XCTest

final class PlayerUITests: XCTestCase {
    func testPlaybackControlsAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-controlsHideSeconds", "30"]
        app.launchEnvironment["HARBOR_TEST_STREAM_URL"] = "http://127.0.0.1:8765/fixture.mp4"
        app.launch()
        let address = app.textFields["streamURL"]
        XCUIDevice.shared.orientation = .landscapeLeft
        let center = app.buttons["centerPlayPause"]
        XCTAssertTrue(center.waitForExistence(timeout: 30))
        let clock = app.staticTexts["playbackClock"]
        let progressed = NSPredicate { _, _ in
            guard clock.exists else { return false }
            let parts = clock.label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && (parts[0] * 60 + parts[1]) >= 1
        }
        expectation(for: progressed, evaluatedWith: clock)
        waitForExpectations(timeout: 25)
        guard clock.exists, clock.label != "0:00" else { capture("Playback failed"); return }
        center.tap() // keep controls visible while paused
        capture("Landscape player")
        app.buttons["Playback speed"].tap()
        app.buttons["1.5×"].tap()
        app.buttons["Anime4K"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Modus A · Balanced'")).firstMatch.tap()
        app.buttons["Fertig"].tap()
        app.buttons["Subtitle language und Stil"].tap()
        XCTAssertTrue(app.buttons["Untertitel ausschalten"].waitForExistence(timeout: 5))
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
