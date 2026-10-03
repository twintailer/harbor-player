import Foundation

struct StremioAddon: Codable, Equatable {
    var transportUrl: URL
    var manifest: Manifest
    struct Manifest: Codable, Equatable {
        var name: String
        var types: [String]?
        var resources: [Resource]?
        var idPrefixes: [String]?
    }
    enum Resource: Codable, Equatable {
        case name(String), descriptor(String, [String]?, [String]?)
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let name = try? container.decode(String.self) { self = .name(name); return }
            let value = try container.decode(Description.self)
            self = .descriptor(value.name, value.types, value.idPrefixes)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .name(let name): try c.encode(name)
            case .descriptor(let name, let types, let prefixes): try c.encode(Description(name: name, types: types, idPrefixes: prefixes))
            }
        }
        private struct Description: Codable { var name: String; var types: [String]?; var idPrefixes: [String]? }
    }
    func supports(_ resource: String, id: String, type: String = "series") -> Bool {
        (manifest.resources ?? []).contains {
            let name: String; let types: [String]?; let prefixes: [String]?
            switch $0 {
            case .name(let value): name = value; types = manifest.types; prefixes = manifest.idPrefixes
            case .descriptor(let value, let t, let p): name = value; types = t ?? manifest.types; prefixes = p ?? manifest.idPrefixes
            }
            return name == resource && (types == nil || types!.contains(type)) && (prefixes == nil || prefixes!.contains { id.hasPrefix($0) })
        }
    }
    func endpoint(_ resource: String, type: String, id: String) -> URL? {
        guard ["http", "https"].contains(transportUrl.scheme?.lowercased() ?? ""), transportUrl.host != nil,
              var parts = URLComponents(url: transportUrl, resolvingAgainstBaseURL: false) else { return nil }
        // Keep the addon's configuration path and query intact.
        if parts.path.hasSuffix("/manifest.json") { parts.path = String(parts.path.dropLast("/manifest.json".count)) }
        else { return nil }
        parts.path += "/\(resource)/\(type)/\(id).json"
        return parts.url
    }
}

struct StremioCredentials: Codable {
    var authKey: String
    var email: String
    var addons: [StremioAddon]
}

struct StremioAPI {
    var base = URL(string: "https://api.strem.io/api")!
    var session = URLSession.shared
    enum Failure: LocalizedError {
        case login, network, noStream, noMetadata
        var errorDescription: String? {
            switch self {
            case .login: return "Anmeldung fehlgeschlagen. Bitte E-Mail und Passwort prüfen."
            case .network: return "Stremio ist gerade nicht erreichbar. Bitte erneut versuchen."
            case .noStream: return "Deine Addons liefern keine direkt abspielbare HTTP-Quelle für diese Folge. Reine Torrent-Quellen benötigen einen Streaming-Server."
            case .noMetadata: return "Die Episodenliste konnte nicht geladen werden."
            }
        }
    }
    func post(_ method: String, _ body: [String: Any]) async throws -> Any {
        var request = URLRequest(url: base.appendingPathComponent(method))
        request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], envelope["error"] == nil,
                  let result = envelope["result"] else { throw method == "login" ? Failure.login : Failure.network }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch let error as Failure { throw error }
        catch { throw Failure.network }
    }
    func login(email: String, password: String) async throws -> StremioCredentials {
        guard let result = try await post("login", ["type": "Login", "email": email, "password": password, "facebook": false]) as? [String: Any],
              let key = result["authKey"] as? String, !key.isEmpty else { throw Failure.login }
        let user = result["user"] as? [String: Any]
        return StremioCredentials(authKey: key, email: user?["email"] as? String ?? email, addons: try await addons(key))
    }
    func addons(_ key: String) async throws -> [StremioAddon] {
        guard let value = try await post("addonCollectionGet", ["type": "AddonCollectionGet", "authKey": key, "update": false]) as? [String: Any],
              let values = value["addons"] as? [[String: Any]] else { throw Failure.network }
        // One unsupported manifest must not discard all other installed addons.
        return values.compactMap { try? JSONDecoder().decode(StremioAddon.self, from: JSONSerialization.data(withJSONObject: $0)) }
    }
    func saveProgress(key: String, request: PlaybackRequest, videoID: String, position: Double, duration: Double, completed: Bool) async throws {
        guard !request.contentID.isEmpty, position.isFinite, duration.isFinite, position >= 0, duration > 0,
              position < 315_576_000, duration < 315_576_000 else { return }
        // A failed read must never turn into an overwrite of an existing bookmark.
        guard let records = try await post("datastoreGet", ["authKey": key, "collection": "libraryItem", "ids": [request.contentID], "all": false]) as? [[String: Any]] else { throw Failure.network }
        let now = ISO8601DateFormatter().string(from: Date())
        var record = records.first { $0["_id"] as? String == request.contentID } ?? ["_id": request.contentID, "type": "series", "name": request.title, "removed": true, "temp": true, "_ctime": now, "posterShape": "poster"]
        var state = record["state"] as? [String: Any] ?? [:]
        let changed = (state["video_id"] as? String).map { $0 != videoID } ?? false
        let oldFlag = (state["flaggedWatched"] as? NSNumber)?.intValue ?? 0
        let watched = completed || position / duration >= 0.9
        state["overallTimeWatched"] = ((state["overallTimeWatched"] as? NSNumber)?.doubleValue ?? 0) + (changed ? ((state["timeWatched"] as? NSNumber)?.doubleValue ?? 0) : 0)
        state["timesWatched"] = ((state["timesWatched"] as? NSNumber)?.intValue ?? 0) + (watched && (changed || oldFlag == 0) ? 1 : 0)
        state["flaggedWatched"] = watched ? 1 : (changed ? 0 : oldFlag)
        state["timeOffset"] = completed ? 0 : Int(position * 1000)
        state["timeWatched"] = Int(position * 1000); state["duration"] = Int(duration * 1000)
        state["video_id"] = videoID; state["lastWatched"] = now
        state["season"] = request.season; state["episode"] = request.episode
        if state["watched"] == nil { state["watched"] = "" }
        if state["noNotif"] == nil { state["noNotif"] = false }
        record["state"] = state; record["_mtime"] = now
        _ = try await post("datastorePut", ["authKey": key, "collection": "libraryItem", "changes": [record]])
    }
}

struct SeriesEpisode: Codable, Equatable, Identifiable {
    var id: String
    var title: String?
    var name: String?
    var season: Int?
    var episode: Int?
    var number: Int?
    var released: String?
    var episodeNumber: Int? { episode ?? number }
    var displayTitle: String { (title ?? name ?? "Folge \(episodeNumber ?? 0)") + " – (\(season ?? 1)×\(episodeNumber ?? 0))" }
    static func ordered(_ episodes: [Self], current: PlaybackRequest, now: Date = Date()) -> [Self] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var ids = Set<String>()
        return episodes.filter { value in
            guard let episode = value.episodeNumber, episode > 0, let season = value.season,
                  season >= 0, (current.season == 0 || season > 0), ids.insert(value.id).inserted else { return false }
            if let date = value.released.flatMap({ formatter.date(from: $0) ?? plain.date(from: $0) }), date > now { return false }
            return true
        }.sorted { ($0.season!, $0.episodeNumber!) < ($1.season!, $1.episodeNumber!) }
    }
}

struct EpisodeStream: Decodable {
    var url: URL?
    var behaviorHints: Hints?
    struct Hints: Decodable { var bingeGroup: String?; var proxyHeaders: Headers? }
    struct Headers: Decodable { var request: [String: String]? }
    var playable: Bool {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return false }
        // Do not silently drop required authentication headers.
        return behaviorHints?.proxyHeaders?.request?.isEmpty != false
    }
}

struct TVEpisodeService {
    var session = URLSession.shared
    func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url); request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 8_000_000 else { throw StremioAPI.Failure.network }
        return try JSONDecoder().decode(T.self, from: data)
    }
    struct Metadata: Decodable { var meta: Meta; struct Meta: Decodable { var videos: [SeriesEpisode]? } }
    struct Streams: Decodable { var streams: [EpisodeStream] }
    func episodes(_ request: PlaybackRequest, addons: [StremioAddon]) async throws -> [SeriesEpisode] {
        guard request.season != nil, request.episode != nil else { return [] }
        var urls = addons.filter { $0.supports("meta", id: request.contentID) }.compactMap { $0.endpoint("meta", type: "series", id: request.contentID) }
        if request.contentID.range(of: #"^tt\d+$"#, options: .regularExpression) != nil {
            urls.append(URL(string: "https://v3-cinemeta.strem.io/meta/series/\(request.contentID).json")!)
        }
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["HARBOR_TEST_EPISODES_URL"], let url = URL(string: raw), ["localhost", "127.0.0.1"].contains(url.host ?? "") { urls = [url] }
        #endif
        for url in urls {
            try Task.checkCancellation()
            if let data = try? await get(url, as: Metadata.self) {
                let ordered = SeriesEpisode.ordered(data.meta.videos ?? [], current: request)
                if ordered.contains(where: { $0.season == request.season && $0.episodeNumber == request.episode }) { return ordered }
            }
        }
        throw StremioAPI.Failure.noMetadata
    }
    func streams(_ addon: StremioAddon, id: String) async -> [EpisodeStream] {
        guard addon.supports("stream", id: id), let url = addon.endpoint("stream", type: "series", id: id) else { return [] }
        return (try? await get(url, as: Streams.self).streams) ?? []
    }
    func resolve(_ target: SeriesEpisode, current: PlaybackRequest, currentVideoID: String, addons: [StremioAddon]) async throws -> URL {
        // Query providers concurrently but preserve installed-addon order when selecting.
        let providers = addons.enumerated().filter { $0.element.supports("stream", id: target.id) }
        let results = await withTaskGroup(of: (Int, [EpisodeStream], [EpisodeStream]).self) { group in
            for (index, addon) in providers {
                group.addTask {
                    async let next = streams(addon, id: target.id)
                    async let old = streams(addon, id: currentVideoID)
                    return await (index, next, old)
                }
            }
            var values: [(Int, [EpisodeStream], [EpisodeStream])] = []
            for await value in group { values.append(value) }
            return values.sorted { $0.0 < $1.0 }
        }
        try Task.checkCancellation()
        // Retain the current provider/release group when it can be identified.
        for (_, candidates, old) in results {
            if let previous = old.first(where: { $0.url == current.url }) {
                if let group = previous.behaviorHints?.bingeGroup,
                   let match = candidates.first(where: { $0.playable && $0.behaviorHints?.bingeGroup == group }), let url = match.url { return url }
                if let url = candidates.first(where: { $0.playable })?.url { return url }
            }
        }
        guard let url = results.flatMap({ $0.1 }).first(where: { $0.playable })?.url else { throw StremioAPI.Failure.noStream }
        return url
    }
    static func callback(_ callback: URL?, contentID: String, videoID: String) -> URL? {
        guard let callback, PlaybackCallback.isSupported(callback), var parts = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return nil }
        if parts.scheme == "https", let fragment = parts.fragment, var route = URLComponents(string: fragment) {
            route.path = "/detail/series/\(contentID)/\(videoID)"; route.queryItems = nil
            parts.fragment = route.string
        } else { parts.host = ""; parts.path = "/detail/series/\(contentID)/\(videoID)"; parts.queryItems = nil }
        return parts.url
    }
}
