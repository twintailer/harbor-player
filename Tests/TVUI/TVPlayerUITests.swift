import XCTest

final class TVPlayerUITests: XCTestCase {
    private let remote = XCUIRemote.shared
    func testRemotePlaybackSettingsAndStremioReturn() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-controlsHideSeconds", "30", "-preferredAudio", "de", "-preferredSubtitles", "de", "-preferForced", "YES", "-seekSeconds", "15"]
        var link = URLComponents(string: "infuse://x-callback-url/play")!
        link.queryItems = [.init(name: "url", value: "http://127.0.0.1:8765/languages.mkv"), .init(name: "position", value: "12"), .init(name: "x-success", value: "stremio:///detail/series/tt123/tt123:1:2")]
        app.launchEnvironment["HARBOR_TEST_STREAM_URL"] = link.url!.absoluteString
        app.launchEnvironment["HARBOR_TEST_CAPTURE_CALLBACK"] = "1"
        app.launch()
        let clock = app.staticTexts["playbackClock"]
        wait("Playback resumes") { self.seconds(clock) >= 12 }
        remote.press(.playPause)
        wait("Remote pauses") { app.buttons["centerPlayPause"].label == "Wiedergabe" }
        XCTAssertTrue(app.buttons["Play-Pause"].hasFocus)
        let start = seconds(clock)
        remote.press(.right)
        XCTAssertTrue(app.buttons["Vorspringen"].hasFocus)
        remote.press(.select)
        wait("Remote skips forward") { abs(self.seconds(clock) - start - 15) <= 1 }
        remote.press(.left)
        remote.press(.left)
        XCTAssertTrue(app.buttons["Zurückspringen"].hasFocus)
        remote.press(.select)
        wait("Remote skips backward") { abs(self.seconds(clock) - start) <= 1 }
        capture("Apple TV Liquid Glass player")
        for _ in 0..<3 { remote.press(.right) }
        XCTAssertTrue(app.buttons["Playback speed"].hasFocus)
        remote.press(.select)
        XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 10))
        capture("Apple TV speed menu")
        remote.press(.menu)
        wait("Menu restores speed button focus") { app.buttons["Playback speed"].hasFocus }
        remote.press(.right)
        XCTAssertTrue(app.buttons["Anime4K"].hasFocus)
        remote.press(.select)
        wait("Anime4K menu opens") { app.buttons["anime-off"].hasFocus }
        remote.press(.down)
        XCTAssertTrue(app.buttons["anime-fast"].hasFocus)
        remote.press(.select)
        wait("Anime4K enabled on TV") { app.descendants(matching: .any)["animeActive"].exists }
        remote.press(.menu)
        wait("Shader menu restores focus") { app.buttons["Anime4K"].hasFocus }
        capture("Apple TV Anime4K active")
        remote.press(.right)
        XCTAssertTrue(app.buttons["Audio language"].hasFocus)
        remote.press(.select)
        wait("German audio chosen automatically") { app.buttons["track-audio-1"].value as? String == "selected" }
        remote.press(.menu)
        wait("Audio button focus restored") { app.buttons["Audio language"].hasFocus }
        remote.press(.right)
        XCTAssertTrue(app.buttons["Subtitle language"].hasFocus)
        remote.press(.select)
        wait("Forced German subtitles chosen") { app.buttons["track-sub-1"].value as? String == "selected" }
        capture("Apple TV subtitle menu")
        remote.press(.menu)
        wait("Subtitle menu dismisses") { app.buttons["Subtitle language"].hasFocus && !app.buttons["closeSettings"].exists }
        remote.press(.menu)
        wait("Controls hidden") { !app.staticTexts["playbackClock"].exists }
        capture("Apple TV clean paused video")
        remote.press(.playPause)
        wait("Remote resumes and reveals controls") { app.buttons["centerPlayPause"].label == "Pause" }
        remote.press(.playPause)
        wait("Paused before returning") { app.buttons["centerPlayPause"].label == "Wiedergabe" }
        let position = seconds(clock)
        remote.press(.menu)
        remote.press(.menu)
        let returned = app.staticTexts["returnCallback"]
        XCTAssertTrue(returned.waitForExistence(timeout: 15))
        let callback = try XCTUnwrap(URLComponents(string: returned.label))
        XCTAssertEqual(callback.scheme, "stremio")
        XCTAssertEqual(callback.path, "/detail/series/tt123/tt123:1:2")
        let progress = try XCTUnwrap(callback.queryItems?.first { $0.name == "position" }?.value.flatMap(Int.init))
        XCTAssertLessThanOrEqual(abs(progress - position), 1)
        capture("Apple TV Stremio return")
    }
    func testAutomaticIntroAndRecap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-controlsHideSeconds", "30", "-autoSkipIntro", "YES", "-autoSkipRecap", "YES"]
        var link = URLComponents(string: "infuse://x-callback-url/play")!
        link.queryItems = [.init(name: "url", value: "http://127.0.0.1:8765/skip-chapters.mkv"), .init(name: "position", value: "2")]
        app.launchEnvironment["HARBOR_TEST_STREAM_URL"] = link.url!.absoluteString
        app.launch()
        let clock = app.staticTexts["playbackClock"]
        wait("TV automatically skips recap and intro") { self.seconds(clock) >= 30 }
        XCTAssertLessThan(seconds(clock), 40)
        capture("Apple TV automatic intro and recap")
        app.terminate()
    }
    private func seconds(_ clock: XCUIElement) -> Int {
        guard clock.exists else { return -1 }
        let values = clock.label.split(separator: ":").compactMap { Int($0) }
        return values.count == 2 ? values[0] * 60 + values[1] : -1
    }
    private func wait(_ name: String, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 30)
        if result != .completed { capture(name) }
        XCTAssertEqual(result, .completed, name)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
