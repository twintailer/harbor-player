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
        print("Playback URL and subtitle mapping tests passed")
    }
}
