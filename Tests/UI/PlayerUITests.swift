import XCTest

final class PlayerUITests: XCTestCase {
    func testPlaybackControlsAndSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-controlsHideSeconds", "30", "-preferredAudio", "de", "-preferredSubtitles", "de", "-preferForced", "YES", "-seekSeconds", "15"]
        var link = URLComponents(string: "infuse://x-callback-url/play")!
        link.queryItems = [.init(name: "url", value: "http://127.0.0.1:8765/languages.mkv"), .init(name: "position", value: "12"), .init(name: "x-success", value: "stremio:///detail/series/tt123/tt123:1:2")]
        app.launchEnvironment["HARBOR_TEST_STREAM_URL"] = link.url!.absoluteString
        app.launchEnvironment["HARBOR_TEST_CAPTURE_CALLBACK"] = "1"
        app.launch()
        let center = app.buttons["centerPlayPause"]
        XCTAssertTrue(center.waitForExistence(timeout: 30))
        waitUntil("Player rotates to landscape while the phone stays portrait") {
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }
        let clock = app.staticTexts["playbackClock"]
        waitUntil("Playback starts") { self.seconds(clock) > 0 }
        XCTAssertGreaterThanOrEqual(seconds(clock), 12, "The first playback position must honor Stremio resume")
        center.tap()
        waitUntil("Paused") { center.label == "Wiedergabe" }
        let start = seconds(clock)
        capture("Before double tap")
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.42))
        right.doubleTap()
        capture("After double tap")
        waitUntil("Double tap right seeks 15 seconds") { abs(self.seconds(clock) - start - 15) <= 1 }
        left.doubleTap()
        waitUntil("Double tap left seeks back 15 seconds") { abs(self.seconds(clock) - start) <= 1 }
        XCTAssertEqual(center.label, "Wiedergabe", "Seeking must preserve pause state")
        capture("Automatic landscape and resumed playback")

        app.buttons["Audio language"].tap()
        let german = app.buttons["track-audio-1"]
        waitUntil("Preferred German audio selected") { german.value as? String == "selected" }
        app.buttons["Fertig"].tap()
        app.buttons["Subtitle language und Stil"].tap()
        let forced = app.buttons["track-sub-1"]
        let full = app.buttons["track-sub-2"]
        waitUntil("Forced German subtitles for German audio") { forced.value as? String == "selected" }
        capture("Forced subtitles with preferred audio")
        app.buttons["Fertig"].tap()
        app.buttons["Audio language"].tap()
        app.buttons["track-audio-2"].tap()
        app.buttons["Fertig"].tap()
        app.buttons["Subtitle language und Stil"].tap()
        waitUntil("Full German subtitles after switching audio to Japanese") { full.value as? String == "selected" }
        capture("Full subtitles with foreign audio")
        app.buttons["Untertitel ausschalten"].tap()
        waitUntil("Explicit subtitle override is retained") { full.value as? String == "unselected" && forced.value as? String == "unselected" }
        app.buttons["Fertig"].tap()
        app.buttons["Playback speed"].tap()
        XCTAssertTrue(app.buttons["Fertig"].waitForExistence(timeout: 5), "The entire tempo button must open its menu")
        capture("Liquid Glass playback speed")
        reveal(app.buttons["1.5×"], in: app)
        app.buttons["1.5×"].tap()
        app.buttons["Anime4K"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Modus A · Balanced'")).firstMatch.tap()
        app.buttons["Fertig"].tap()
        app.buttons["Einstellungen"].tap()
        capture("Liquid Glass settings overview")
        reveal(app.buttons["openLanguagePreferences"], in: app)
        app.buttons["openLanguagePreferences"].tap()
        XCTAssertTrue(app.switches["Forced bevorzugen"].waitForExistence(timeout: 5))
        capture("Preferred languages and controls")
        app.buttons["Fertig"].tap()
        app.buttons["Subtitle language und Stil"].tap()
        reveal(app.buttons["openSubtitleStyle"], in: app)
        app.buttons["openSubtitleStyle"].tap()
        XCTAssertTrue(app.staticTexts["So sehen deine Untertitel aus"].waitForExistence(timeout: 5))
        capture("Subtitle appearance settings")
        app.buttons["Fertig"].tap()
        // Tapping outside a floating menu dismisses it without pausing/seeking.
        app.buttons["Einstellungen"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.4)).tap()
        XCTAssertTrue(center.isHittable)
        // The new narrow timeline still supports direct seeking.
        let timeline = app.descendants(matching: .any).matching(identifier: "playbackTimeline").firstMatch
        XCTAssertTrue(timeline.exists)
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()
        waitUntil("Timeline seeks to 60 percent") { abs(self.seconds(clock) - 36) <= 1 }
        capture("Liquid Glass final player")
        let finalPosition = seconds(clock)
        app.buttons["Player schließen"].tap()
        XCTAssertTrue(app.textFields["streamURL"].waitForExistence(timeout: 15))
        waitUntil("Home returns to portrait") { app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width }
        let returned = app.staticTexts["returnCallback"]
        XCTAssertTrue(returned.waitForExistence(timeout: 10))
        let callback = try XCTUnwrap(URLComponents(string: returned.label))
        XCTAssertEqual(callback.scheme, "stremio")
        XCTAssertEqual(callback.path, "/detail/series/tt123/tt123:1:2")
        let progress = try XCTUnwrap(callback.queryItems?.first { $0.name == "position" }?.value.flatMap(Int.init))
        XCTAssertLessThanOrEqual(abs(progress - finalPosition), 1)
        XCTAssertEqual(callback.queryItems?.first { $0.name == "lastPlayedUrl" }?.value, "http://127.0.0.1:8765/languages.mkv")
        capture("Native Stremio progress callback")
    }
    private func seconds(_ clock: XCUIElement) -> Int {
        guard clock.exists else { return -1 }
        let parts = clock.label.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }
    private func reveal(_ button: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if button.isHittable { return }
            app.scrollViews["playerPanelScroll"].swipeUp()
        }
        XCTAssertTrue(button.isHittable)
    }
    private func waitUntil(_ description: String, timeout: TimeInterval = 25, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed { capture(description) }
        XCTAssertEqual(result, .completed, description)
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
