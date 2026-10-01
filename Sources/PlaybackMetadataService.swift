import Foundation

@MainActor enum PlaybackMetadataService {
    static var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()
    private static var cache: [String: String] = [:]

    static func title(for request: PlaybackRequest, language: String,
                      partial: (String) -> Void = { _ in }) async -> String? {
        guard request.contentID.range(of: #"^tt\d+$"#, options: .regularExpression) != nil else { return nil }
        let type = request.season != nil && request.episode != nil ? "series" : "movie"
        let key = "\(request.contentID):\(request.season ?? 0):\(request.episode ?? 0):\(language)"
        if let cached = cache[key] { return cached }
        var localized = "https://94c8cb9f702d-tmdb-addon.baby-beamup.club/\(language)/meta/\(type)/\(request.contentID).json"
        var cinemeta = "https://v3-cinemeta.strem.io/meta/\(type)/\(request.contentID).json"
        #if DEBUG
        if let base = ProcessInfo.processInfo.environment["HARBOR_TEST_META_URL"], base.hasPrefix("http://127.0.0.1:") {
            localized = base + "/localized.json"; cinemeta = base + "/cinemeta.json"
        }
        #endif
        async let translated = fetch(localized, request: request)
        let original = await fetch(cinemeta, request: request)
        if !Task.isCancelled, let original { partial(original) }
        let preferred = await translated
        guard !Task.isCancelled else { return nil }
        let result = preferred ?? original
        if let result { cache[key] = result }
        return result
    }
    static func display(_ name: String, request: PlaybackRequest) -> String {
        guard let season = request.season, let episode = request.episode else { return name }
        return "\(name) – (\(season)×\(episode))"
    }
    static func fallback(_ request: PlaybackRequest) -> String {
        var name = request.title
        if let range = name.range(of: #"(?i)\bS\d{1,3}[ ._-]*E\d{1,4}\b"#, options: .regularExpression) {
            name = String(name[..<range.lowerBound]).replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return display(name.isEmpty ? "Folge" : name, request: request)
    }
    private static func fetch(_ address: String, request: PlaybackRequest) async -> String? {
        guard let url = URL(string: address), let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let result = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let name: String?
        if let season = request.season, let episode = request.episode {
            let id = "\(request.contentID):\(season):\(episode)"
            let video = result.meta.videos?.first { $0.id == id }
                ?? result.meta.videos?.first { $0.season == season && ($0.episode ?? $0.number) == episode }
            name = video?.title ?? video?.name
        } else { name = result.meta.name }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return display(name, request: request)
    }
    private struct Response: Decodable { let meta: Meta }
    private struct Meta: Decodable { let name: String?; let videos: [Video]? }
    private struct Video: Decodable { let id: String?; let title: String?; let name: String?; let season: Int?; let episode: Int?; let number: Int? }
}
