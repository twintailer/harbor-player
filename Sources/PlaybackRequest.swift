import Foundation

struct PlaybackRequest: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var title: String
    var contentID: String = ""
    var season: Int? = nil
    var episode: Int? = nil
    var isAnime = false
    var start: Double = 0
    var subtitle: URL? = nil
    var successCallback: URL? = nil

    static func parse(_ input: URL) throws -> PlaybackRequest {
        let scheme = input.scheme?.lowercased() ?? ""
        if ["http", "https"].contains(scheme), input.host != nil {
            return PlaybackRequest(url: input, title: input.lastPathComponent)
        }
        // Stremio's Outplayer integration replaces only the HTTP scheme.
        if scheme == "outplayer", !["play", "open"].contains(input.host ?? "") {
            let raw = input.absoluteString
            let tail = String(raw.dropFirst("outplayer:".count))
            let translated = tail.hasPrefix("http") ? tail : "https:" + tail
            if let url = URL(string: translated) { return try parse(url) }
        }
        guard ["harborplayer", "outplayer", "vlc-x-callback", "infuse"].contains(scheme),
              let parts = URLComponents(url: input, resolvingAgainstBaseURL: false),
              let raw = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { throw RequestError.invalidURL }
        func value(_ key: String) -> String? { parts.queryItems?.first(where: { $0.name == key })?.value }
        var result = PlaybackRequest(url: url, title: value("title") ?? value("filename") ?? url.lastPathComponent)
        result.contentID = value("id") ?? ""
        result.season = value("season").flatMap(Int.init)
        result.episode = value("episode").flatMap(Int.init)
        result.isAnime = value("anime") == "1" || result.contentID.hasPrefix("mal:") || result.contentID.hasPrefix("kitsu:")
        let start = (value("position") ?? value("start")).flatMap(Double.init) ?? 0
        result.start = start.isFinite && start >= 0 && start <= 315_576_000 ? start : 0
        if let raw = value("x-success"), let callback = URL(string: raw), PlaybackCallback.isSupported(callback) {
            result.successCallback = callback
        }
        if let raw = value("subtitle") ?? value("sub"), let sub = URL(string: raw), ["http", "https"].contains(sub.scheme ?? "") {
            result.subtitle = sub
        }
        return result
    }
    enum RequestError: LocalizedError {
        case invalidURL
        var errorDescription: String? { "Bitte eine gültige HTTP(S)-Stream-URL öffnen." }
    }
}

enum PlaybackCallback {
    // Only return media URLs to Stremio, never to an arbitrary callback host.
    static func isSupported(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "stremio" { return true }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == "web.stremio.com" && url.user == nil && url.password == nil
    }

    static func make(request: PlaybackRequest, position: Double, loaded: Bool, web: Bool = false) -> URL? {
        guard loaded, position.isFinite, position >= 0, position <= 315_576_000,
              let callback = request.successCallback, isSupported(callback),
              var target = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return nil }
        let additions = [URLQueryItem(name: "position", value: String(Int(position))),
                         URLQueryItem(name: "lastPlayedUrl", value: request.url.absoluteString)]
        if web && target.scheme == "stremio" {
            // Stremio Web uses hash routes. Queries belong INSIDE the fragment.
            var route = URLComponents()
            route.percentEncodedPath = target.percentEncodedPath
            if let host = target.host, !host.isEmpty { route.percentEncodedPath = "/" + host + target.percentEncodedPath }
            route.queryItems = target.queryItems
            var webTarget = URLComponents(string: "https://web.stremio.com/")!
            webTarget.percentEncodedFragment = route.string
            target = webTarget
        }
        if target.scheme == "https", let fragment = target.percentEncodedFragment, !fragment.isEmpty {
            guard var route = URLComponents(string: fragment) else { return nil }
            route.queryItems = replacingProgress(route.queryItems, with: additions)
            target.percentEncodedFragment = route.string
        } else {
            target.queryItems = replacingProgress(target.queryItems, with: additions)
        }
        return target.url
    }

    private static func replacingProgress(_ existing: [URLQueryItem]?, with values: [URLQueryItem]) -> [URLQueryItem] {
        (existing ?? []).filter { !["position", "lastPlayedUrl"].contains($0.name) } + values
    }
}
