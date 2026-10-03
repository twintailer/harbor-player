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
    var contentType: String? = nil

    static func parse(_ input: URL) throws -> PlaybackRequest {
        let scheme = input.scheme?.lowercased() ?? ""
        if ["http", "https"].contains(scheme), input.host != nil {
            var result = PlaybackRequest(url: input, title: input.lastPathComponent)
            result.inferContentIdentity()
            return result
        }
        // Stremio's Outplayer integration replaces only the HTTP scheme.
        if scheme == "outplayer", !["play", "open"].contains(input.host ?? "") {
            let raw = input.absoluteString
            let tail = String(raw.dropFirst("outplayer:".count))
            let translated = tail.hasPrefix("http") ? tail : "https:" + tail
            if let url = URL(string: translated) { return try parse(url) }
        }
        guard ["kairoplayer", "harborplayer", "outplayer", "vlc-x-callback", "infuse"].contains(scheme),
              let parts = URLComponents(url: input, resolvingAgainstBaseURL: false),
              let raw = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { throw RequestError.invalidURL }
        func value(_ key: String) -> String? { parts.queryItems?.first(where: { $0.name == key })?.value }
        var result = PlaybackRequest(url: url, title: value("title") ?? value("filename") ?? url.lastPathComponent)
        result.contentID = value("id") ?? ""
        result.contentType = value("type")
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
        result.inferContentIdentity()
        return result
    }

    /// Native Stremio's Infuse protocol carries the media identity in x-success,
    /// not in standalone id/season/episode parameters.
    mutating func inferContentIdentity() {
        if let callback = successCallback, let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false) {
            let route = parts.scheme == "https"
                ? parts.fragment.flatMap { URLComponents(string: $0)?.path } ?? parts.path : parts.path
            let fields = route.split(separator: "/").map(String.init)
            if let detail = fields.firstIndex(of: "detail"), fields.count > detail + 2 {
                let type = fields[detail + 1]
                contentType = contentType ?? type
                let meta = fields[detail + 2]
                let video = fields.count > detail + 3 ? fields[detail + 3] : meta
                applyIdentity(meta, video: video, type: type)
            }
        }
        if !contentID.isEmpty { applyIdentity(contentID, video: contentID, type: nil) }
        if contentType != "movie", season == nil || episode == nil {
            let text = title.removingPercentEncoding ?? title
            if let range = text.range(of: #"(?i)\bS(\d{1,3})[ ._-]*E(\d{1,4})\b"#, options: .regularExpression) {
                let numbers = text[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if numbers.count == 2 { season = season ?? numbers[0]; episode = episode ?? numbers[1] }
            }
        }
        isAnime = isAnime || ["mal:", "kitsu:", "anilist:"].contains { contentID.hasPrefix($0) }
    }

    private mutating func applyIdentity(_ meta: String, video: String, type: String?) {
        let fields = meta.split(separator: ":").map(String.init)
        guard let head = fields.first else { return }
        let base: String
        var prefixCount = 1
        if head.range(of: #"^tt\d+$"#, options: .regularExpression) != nil {
            base = head
        } else if ["mal", "kitsu", "anilist"].contains(head), fields.count >= 2, Int(fields[1]) != nil {
            base = "\(head):\(fields[1])"; prefixCount = 2
        } else if head == "tmdb", fields.count >= 2 {
            let explicitType = ["tv", "movie"].contains(fields[1])
            let index = explicitType ? 2 : 1
            guard fields.count > index, Int(fields[index]) != nil else { return }
            let kind = explicitType ? fields[1] : (type == "movie" ? "movie" : "tv")
            base = "tmdb:\(kind):\(fields[index])"; prefixCount = index + 1
        } else { return }
        // Explicit parameters take priority over callback/file inference.
        if contentID.isEmpty || contentID == meta { contentID = base }
        guard contentID == base else { return }
        let numbers = video.split(separator: ":").dropFirst(prefixCount).compactMap { Int($0) }
        if numbers.count >= 2 { season = season ?? numbers[0]; episode = episode ?? numbers[1] }
        else if numbers.count == 1, head != "tt" { episode = episode ?? numbers[0] }
        if episode != nil, season == nil, ["mal", "kitsu", "anilist"].contains(head) { season = 1 }
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
