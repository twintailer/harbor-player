import Foundation

/// Provider fixtures isolate regressions from community coverage/network outages.
@main struct IntroLookupTests {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderFixture.self]
        IntroSkipService.session = URLSession(configuration: configuration)
        let resolved = await IntroSkipService.resolveAnimeEpisode(contentID: "tt2560140", season: 3, episode: 13)
        precondition(resolved?.malID == 38524 && resolved?.episode == 1,
                     "Season 3 episode 13 must map to part-two MAL episode 1")
        let unknown = await IntroSkipService.resolveAnimeEpisode(contentID: "tt2560140", season: 9, episode: 99)
        precondition(unknown == nil, "Do not pick a random MAL season")
        let anime = await IntroSkipService.segments(contentID: "tt2560140", season: 3, episode: 13,
                                                   duration: 1440, isAnime: false, chapters: [])
        precondition(anime.contains { $0.kind == .intro && $0.start == 10 && $0.end == 100 && $0.source == .aniSkip },
                     "IMDb anime must work without a manually selected anime flag")
        precondition(anime.contains { $0.kind == .recap && $0.start == 0 && $0.end == 10 })
        let tv = await IntroSkipService.segments(contentID: "tt9999", season: 2, episode: 4,
                                                duration: 1800, isAnime: false, chapters: [])
        precondition(tv.contains { $0.kind == .recap && $0.start == 0 && $0.end == 20 })
        precondition(tv.contains { $0.kind == .intro && $0.start == 20 && $0.end == 100 })
        precondition(tv.contains { $0.kind == .outro && $0.end == 1800 }, "Null credits end means end of media")
        let raw = try PlaybackRequest.parse(URL(string: "https://example.org/Attack.on.Titan.S03E13.mkv")!)
        let identified = await IntroSkipService.identify(raw)
        precondition(identified.contentID == "tt2560140" && identified.season == 3 && identified.episode == 13)
        let ambiguous = try PlaybackRequest.parse(URL(string: "https://example.org/Remake.S01E01.mkv")!)
        let unidentified = await IntroSkipService.identify(ambiguous)
        precondition(unidentified.contentID.isEmpty, "Ambiguous filenames must not skip unrelated scenes")
        print("Automatic identity, split-cour mapping, AniSkip and TheIntroDB v3 tests passed")
    }
}

private final class ProviderFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        func value(_ key: String) -> String? { parts.queryItems?.first { $0.name == key }?.value }
        var json = "{}"
        var status = 200
        switch url.host {
        case "api.ani.zip":
            if value("imdb_id") == "tt2560140" || value("mal_id") == "16498" {
                json = #"{"mappings":{"mal_id":16498,"imdb_id":"tt2560140"},"episodes":{"1":{"seasonNumber":1,"episodeNumber":1}}}"#
            } else if value("mal_id") == "38524" {
                json = #"{"mappings":{"mal_id":38524,"imdb_id":"tt2560140"},"episodes":{"1":{"seasonNumber":3,"episodeNumber":13}}}"#
            } else { status = 404 }
        case "arm.haglund.dev":
            json = value("id") == "tt2560140" ? #"[{"myanimelist":16498},{"myanimelist":38524}]"# : "[]"
        case "api.aniskip.com":
            precondition(url.path == "/v2/skip-times/38524/1")
            precondition(value("episodeLength") == "1440")
            json = #"{"found":true,"results":[{"skipType":"op","interval":{"startTime":10,"endTime":100}},{"skipType":"recap","interval":{"startTime":0,"endTime":10}}]}"#
        case "api.theintrodb.org":
            precondition(url.path == "/v3/media" && value("duration_ms") != nil)
            if value("imdb_id") == "tt9999" {
                precondition(value("season") == "2" && value("episode") == "4")
                json = #"{"recap":[{"start_ms":null,"end_ms":20000}],"intro":[{"start_ms":20000,"end_ms":100000}],"credits":[{"start_ms":1700000,"end_ms":null}]}"#
            }
        case "v3-cinemeta.strem.io":
            json = url.path.contains("Remake")
                ? #"{"metas":[{"id":"tt1","name":"Remake"},{"id":"tt2","name":"Remake"}]}"#
                : #"{"metas":[{"id":"tt2560140","name":"Attack on Titan"}]}"#
        default: status = 404
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
