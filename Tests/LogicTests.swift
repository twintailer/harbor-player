import Foundation

@main struct LogicTests {
    static func main() throws {
        let stream = "https://example.org/video.mkv?token=a%2Fb&x=one+two"
        var link = URLComponents(string: "harborplayer://play")!
        link.queryItems = [.init(name: "url", value: stream), .init(name: "id", value: "mal:5114"), .init(name: "episode", value: "2"), .init(name: "start", value: "nan")]
        let request = try PlaybackRequest.parse(link.url!)
        precondition(request.url.absoluteString == stream, "Do not double-decode signed stream URLs")
        precondition(request.isAnime && request.episode == 2 && request.start == 0)
        let outplayer = try PlaybackRequest.parse(URL(string: "outplayer://example.org/video?token=a%2Fb")!)
        precondition(outplayer.url.absoluteString == "https://example.org/video?token=a%2Fb")
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
        print("Playback URL and subtitle mapping tests passed")
    }
}
