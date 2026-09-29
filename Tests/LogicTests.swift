import Foundation

@main struct LogicTests {
    @MainActor static func main() throws {
        let stream = "https://example.org/video.mkv?token=a%2Fb&x=one+two"
        var link = URLComponents(string: "harborplayer://play")!
        link.queryItems = [.init(name: "url", value: stream), .init(name: "id", value: "mal:5114"), .init(name: "episode", value: "2"), .init(name: "start", value: "nan")]
        let request = try PlaybackRequest.parse(link.url!)
        precondition(request.url.absoluteString == stream, "Do not double-decode signed stream URLs")
        precondition(request.isAnime && request.episode == 2 && request.start == 0)
        let outplayer = try PlaybackRequest.parse(URL(string: "outplayer://example.org/video?token=a%2Fb")!)
        precondition(outplayer.url.absoluteString == "https://example.org/video?token=a%2Fb")
        var vlc = URLComponents(string: "vlc-x-callback://x-callback-url/stream")!
        vlc.queryItems = [.init(name: "url", value: "http://192.168.1.2:11470/video?x=a%2Fb&y=2")]
        let local = try PlaybackRequest.parse(vlc.url!)
        precondition(local.url.absoluteString == "http://192.168.1.2:11470/video?x=a%2Fb&y=2")
        for invalid in ["file:///etc/passwd", "magnet:?xt=x", "harborplayer://play?url=javascript%3Aalert(1)"] {
            do { _ = try PlaybackRequest.parse(URL(string: invalid)!); fatalError("Accepted unsafe scheme") } catch {}
        }
        var infuse = URLComponents(string: "infuse://x-callback-url/play")!
        infuse.queryItems = [.init(name: "url", value: stream), .init(name: "filename", value: "Episode 2"), .init(name: "position", value: "1234"), .init(name: "x-success", value: "stremio:///detail/series/tt123/tt123:1:2?keep=yes&position=1")]
        let resumed = try PlaybackRequest.parse(infuse.url!)
        precondition(resumed.start == 1234 && resumed.title == "Episode 2" && resumed.url.absoluteString == stream)
        let callback = PlaybackCallback.make(request: resumed, position: 1250.99, loaded: true)!
        let returned = URLComponents(url: callback, resolvingAgainstBaseURL: false)!
        precondition(returned.scheme == "stremio" && returned.path == "/detail/series/tt123/tt123:1:2")
        precondition(returned.queryItems?.filter { $0.name == "position" }.count == 1)
        precondition(returned.queryItems?.first { $0.name == "position" }?.value == "1250", "Callback uses seconds, not milliseconds")
        precondition(returned.queryItems?.first { $0.name == "lastPlayedUrl" }?.value == stream)
        precondition(returned.queryItems?.first { $0.name == "keep" }?.value == "yes")
        precondition(PlaybackCallback.make(request: resumed, position: 0, loaded: false) == nil)
        precondition(PlaybackCallback.make(request: request, position: 10, loaded: true) == nil)
        for invalid in [Double.nan, Double.infinity, -1, 315_576_001] {
            precondition(PlaybackCallback.make(request: resumed, position: invalid, loaded: true) == nil)
        }
        for value in ["nan", "-10", "inf", "315576001"] {
            var invalid = infuse
            invalid.queryItems = infuse.queryItems!.filter { $0.name != "position" } + [.init(name: "position", value: value)]
            let parsed = try PlaybackRequest.parse(invalid.url!)
            precondition(parsed.start == 0)
        }
        precondition(!PlaybackCallback.isSupported(URL(string: "https://web.stremio.com.evil.example/")!))
        precondition(!PlaybackCallback.isSupported(URL(string: "https://user@web.stremio.com/")!))
        let web = PlaybackCallback.make(request: resumed, position: 20, loaded: true, web: true)!
        let webParts = URLComponents(url: web, resolvingAgainstBaseURL: false)!
        let route = URLComponents(string: webParts.percentEncodedFragment!)!
        precondition(webParts.host == "web.stremio.com" && webParts.query == nil)
        precondition(route.path == "/detail/series/tt123/tt123:1:2")
        precondition(route.queryItems?.first { $0.name == "lastPlayedUrl" }?.value == stream)

        func track(_ id: Int, _ type: String, _ lang: String, forced: Bool = false, title: String = "", defaultTrack: Bool = false, hearingImpaired: Bool = false) -> MPVTrack {
            MPVTrack(id: id, type: type, title: title, lang: lang, selected: false, external: false, forced: forced, defaultTrack: defaultTrack, hearingImpaired: hearingImpaired, codec: "", externalFilename: "")
        }
        let german = track(1, "audio", "ger")
        let japanese = track(2, "audio", "jpn")
        let forced = track(3, "sub", "deu", forced: true)
        let full = track(4, "sub", "de-DE")
        let english = track(5, "sub", "en")
        let tracks = [german, japanese, forced, full, english]
        var preferences = TrackPreferences(audio: "de", subtitles: "de")
        precondition(preferences.preferredAudio(in: tracks)?.id == german.id)
        precondition(preferences.preferredSubtitle(in: tracks, actualAudio: german) == forced.id)
        precondition(preferences.preferredSubtitle(in: tracks, actualAudio: japanese) == full.id)
        precondition(preferences.preferredSubtitle(in: [forced, english], actualAudio: japanese) == -1)
        precondition(preferences.preferredSubtitle(in: [full, english], actualAudio: german) == -1)
        precondition(preferences.preferredAudio(in: [japanese]) == nil)
        precondition(preferences.preferredSubtitle(in: tracks, actualAudio: nil) == full.id)
        precondition(TrackPreferences.isForced(track(6, "sub", "de", title: "German FORCED")))
        precondition(!TrackPreferences.isForced(track(6, "sub", "de", title: "Unforced dialogue")))
        preferences.preferForced = false
        precondition(preferences.preferredSubtitle(in: tracks, actualAudio: german) == full.id)
        precondition(preferences.preferredSubtitle(in: [full, track(7, "sub", "de", defaultTrack: true, hearingImpaired: true)], actualAudio: german) == full.id)
        preferences.subtitles = "en"
        precondition(preferences.preferredSubtitle(in: tracks, actualAudio: german) == english.id)
        var style = SubtitleSettings()
        precondition(style.options["sub-ass-override"] == "strip")
        precondition(style.options["sub-color"] == "#FFFFFFFF")
        style.style = "box"; style.boxOpacity = 0.6; style.opacity = 0.5
        precondition(style.options["sub-back-color"] == "#4C000000")
        style.style = "outline"; style.borderSize = 0
        precondition(style.options["sub-border-size"] == "1.0")
        let chapters = [MediaChapter(title: "Opening", start: 20, end: 110), MediaChapter(title: "Cold open", start: 0, end: 20), MediaChapter(title: "Unexpected encounter", start: 800, end: 1000), MediaChapter(title: "ED", start: 1300, end: 1390)]
        let segments = IntroSkipService.chapterSegments(chapters, duration: 1440)
        precondition(segments.count == 2, "Do not skip story chapters containing 'ed' or cold opens")
        let merged = IntroSkipService.merge([segments, [SkipSegment(kind: .intro, start: 30, end: 100, source: .aniSkip), SkipSegment(kind: .intro, start: .nan, end: 10, source: .aniSkip)]], duration: 1440)
        precondition(merged.count == 2, "Reject overlapping and non-finite segments")
        print("Playback URLs, Stremio progress, language policy, subtitle style and intro tests passed")
    }
}
