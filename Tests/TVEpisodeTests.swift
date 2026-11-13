import Foundation

@main struct TVEpisodeTests {
    static func main() async throws {
        let bitmapVideos = (1...20).map { (episode: Int) in SeriesEpisode(id: "tt0:1:\(episode)", season: 1, episode: episode) }
        let original = "tt0:1:5:5:eJyTZwAAAEAAIA=="
        let updated = try StremioWatched.mark(original, videoID: "tt0:1:16", videos: bitmapVideos)
        precondition(updated.hasPrefix("tt0:1:16:16:"), "Anchor must use bit index, not byte index")
        precondition(updated == "tt0:1:16:16:eJyTb2AAAAFgAKA=", "Preserve episodes 1–5 and set only episode 16 (independent zlib fixture)")
        let repeated = try StremioWatched.mark(updated, videoID: "tt0:1:16", videos: bitmapVideos)
        precondition(updated == repeated, "Repeated completion must preserve history")
        let special = SeriesEpisode(id: "tt0:0:1", season: 0, episode: 1)
        let shifted = try StremioWatched.mark(original, videoID: special.id, videos: [special] + bitmapVideos)
        precondition(shifted.hasPrefix("tt0:1:5:6:"), "New specials must shift existing watched bits")
        precondition(shifted == "tt0:1:5:6:eJyzZ2AAAADAAEA=", "Preserve earlier watched episodes after shifting")
        do {
            _ = try StremioWatched.mark("invalid", videoID: "tt0:1:1", videos: bitmapVideos)
            preconditionFailure("Malformed history must not be overwritten")
        } catch StremioAPI.Failure.network { }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EpisodeFixture.self]
        let session = URLSession(configuration: config)
        let api = StremioAPI(base: URL(string: "https://fixture.invalid/api")!, session: session)
        let credentials = try await api.login(email: "fixture@example.invalid", password: "fixture-password")
        precondition(credentials.authKey == "fixture-key" && credentials.addons.count == 2)
        do { _ = try await api.login(email: "fixture@example.invalid", password: "wrong"); preconditionFailure("Invalid credentials must fail") }
        catch StremioAPI.Failure.login { }
        let addon = credentials.addons[0]
        precondition(addon.supports("stream", id: "tt123:1:2"))
        precondition(!addon.supports("stream", id: "kitsu:1:2"))
        precondition(!addon.supports("stream", id: "tt123", type: "movie"))
        precondition(addon.endpoint("stream", type: "series", id: "tt123:2:1")!.path == "/secret-config/stream/series/tt123:2:1.json")
        var request = PlaybackRequest(url: URL(string: "https://media.invalid/current.mkv")!, title: "Series", contentID: "tt123", season: 1, episode: 2)
        let service = TVEpisodeService(session: session)
        let episodes = try await service.episodes(request, addons: credentials.addons)
        precondition(episodes.map(\.id) == ["tt123:1:1", "tt123:1:2", "tt123:2:1"], "Sort across seasons, remove specials, duplicates and unreleased episodes")
        let target = episodes[2]
        let stream = try await service.resolve(target, current: request, currentVideoID: "tt123:1:2", addons: credentials.addons)
        precondition(stream.absoluteString == "https://media.invalid/matching.mkv", "Prefer same provider/release group over the first source")
        do { _ = try await service.resolve(SeriesEpisode(id: "tt123:9:9", season: 9, episode: 9), current: request, currentVideoID: "tt123:1:2", addons: credentials.addons); preconditionFailure("Torrent-only response is not playable") }
        catch StremioAPI.Failure.noStream { }
        let callback = TVEpisodeService.callback(URL(string: "stremio:///detail/series/tt123/tt123:1:2?position=45"), contentID: request.contentID, videoID: target.id)!
        request.url = stream; request.season = 2; request.episode = 1; request.successCallback = callback
        let outgoing = PlaybackCallback.make(request: request, position: 5, loaded: true)!
        precondition(outgoing.path == "/detail/series/tt123/tt123:2:1")
        precondition(URLComponents(url: outgoing, resolvingAgainstBaseURL: false)!.queryItems!.contains { $0.name == "position" && $0.value == "5" })
        let web = TVEpisodeService.callback(URL(string: "https://web.stremio.com/#/detail/series/tt123/tt123:1:2"), contentID: "tt123", videoID: target.id)!
        precondition(web.fragment == "/detail/series/tt123/tt123:2:1")
        precondition(TVEpisodeService.callback(URL(string: "https://evil.invalid/"), contentID: "tt123", videoID: target.id) == nil)
        try await api.saveProgress(key: credentials.authKey, request: request, videoID: target.id, position: 60, duration: 60, completed: true)
        precondition(EpisodeFixture.saved["removed"] as? Bool == false && EpisodeFixture.saved["temp"] as? Bool == false, "Progress preserves bookmarks")
        let state = EpisodeFixture.saved["state"] as! [String: Any]
        precondition(state["timeOffset"] as? Int == 0 && state["video_id"] as? String == target.id && state["customFlag"] as? String == "preserved")
        precondition((state["watched"] as? String)?.hasPrefix("tt123:2:1:") == true, "Completed episodes must write the Stremio watched bitmap")
        try await api.saveProgress(key: credentials.authKey, request: request, videoID: "tt123:2:2", position: 15, duration: 60, completed: false)
        let nextState = EpisodeFixture.saved["state"] as! [String: Any]
        precondition(nextState["timeOffset"] as? Int == 15000 && nextState["watched"] as? String == state["watched"] as? String, "Starting the next episode preserves the watched episode and stores its own position")
        EpisodeFixture.dropWrites = true
        do {
            try await api.saveProgress(key: credentials.authKey, request: request, videoID: "tt123:2:2", position: 20, duration: 60, completed: false)
            preconditionFailure("A successful HTTP response without a stored update must fail verification")
        } catch StremioAPI.Failure.unconfirmedSave { }
        EpisodeFixture.dropWrites = false
        EpisodeFixture.rejectWrites = true
        do {
            try await api.saveProgress(key: credentials.authKey, request: request, videoID: "tt123:2:2", position: 20, duration: 60, completed: false)
            preconditionFailure("Rejected account writes must be visible")
        } catch StremioAPI.Failure.rejected(let method, let code) { precondition(method == "datastorePut" && code == 401) }
        EpisodeFixture.rejectWrites = false
        let pending = StremioPendingProgress(request, videoID: target.id, position: 60, duration: 60, completed: true)
        let restored = try JSONDecoder().decode(StremioPendingProgress.self, from: JSONEncoder().encode(pending))
        precondition(restored.videoID == target.id && restored.completed && restored.request.contentID == request.contentID)
        let movie = try PlaybackRequest.parse(URL(string: "infuse://x-callback-url/play?url=https%3A%2F%2Fmedia.invalid%2FS01E02.mkv&x-success=stremio%3A%2F%2F%2Fdetail%2Fmovie%2Ftt123")!)
        precondition(movie.contentType == "movie" && movie.season == nil && movie.episode == nil)
        print("Stremio login/import, addon filters, exact episode order, stream resolution, movie exclusion, progress merge and callbacks passed")
    }
}

private final class EpisodeFixture: URLProtocol {
    static var saved: [String: Any] = [:]
    static var dropWrites = false
    static var rejectWrites = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        var body: [String: Any] = [:]
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 8192), data = Data()
            while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
            body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        } else if let data = request.httpBody { body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
        let addon: [String: Any] = ["transportUrl": "https://fixture.invalid/secret-config/manifest.json", "manifest": ["name": "Fixture", "types": ["series"], "idPrefixes": ["tt"], "resources": ["meta", ["name": "stream", "types": ["series"], "idPrefixes": ["tt"]]]]]
        let other: [String: Any] = ["transportUrl": "https://fixture.invalid/other/manifest.json", "manifest": ["name": "Other", "types": ["series"], "resources": ["stream"]]]
        let response: [String: Any]
        switch url.lastPathComponent {
        case "login":
            precondition(body["type"] as? String == "Login")
            response = body["password"] as? String == "fixture-password" ? ["result": ["authKey": "fixture-key", "user": ["email": "fixture@example.invalid"]]] : ["error": ["code": 2, "message": "bad credentials"]]
        case "addonCollectionGet":
            precondition(body["authKey"] as? String == "fixture-key" && body["update"] as? Bool == false)
            response = ["result": ["addons": [addon, other, ["transportUrl": "broken"]]]]
        case "datastoreGet": response = ["result": [Self.saved.isEmpty ? ["_id": "tt123", "removed": false, "temp": false, "state": ["customFlag": "preserved"]] : Self.saved]]
        case "datastorePut":
            if Self.rejectWrites { response = ["error": ["code": 401]] }
            else {
                if !Self.dropWrites { Self.saved = (body["changes"] as! [[String: Any]])[0] }
                response = ["result": true]
            }
        default:
            precondition(body.isEmpty, "Account keys must never be sent to addons")
            if url.path.contains("/meta/") {
                response = ["meta": ["videos": [
                    ["id": "tt123:2:1", "season": 2, "episode": 1, "title": "Season two"],
                    ["id": "tt123:1:2", "season": 1, "episode": 2],
                    ["id": "tt123:1:1", "season": 1, "episode": 1],
                    ["id": "tt123:0:1", "season": 0, "episode": 1],
                    ["id": "tt123:3:1", "season": 3, "episode": 1, "released": "2999-01-01T00:00:00Z"],
                    ["id": "tt123:1:1", "season": 1, "episode": 1]
                ]]]
            } else if url.lastPathComponent == "tt123:9:9.json" { response = ["streams": [["infoHash": "not-http"], ["externalUrl": "https://external.invalid"]]] }
            else if url.lastPathComponent == "tt123:1:2.json" { response = ["streams": [["url": "https://media.invalid/current.mkv", "behaviorHints": ["bingeGroup": "release-A"]]]] }
            else { response = ["streams": [
                ["url": "https://media.invalid/first.mkv", "behaviorHints": ["bingeGroup": "release-B"]],
                ["url": "https://media.invalid/matching.mkv", "behaviorHints": ["bingeGroup": "release-A"]]
            ]] }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
