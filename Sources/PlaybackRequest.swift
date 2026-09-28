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
        guard ["harborplayer", "outplayer"].contains(scheme),
              let parts = URLComponents(url: input, resolvingAgainstBaseURL: false),
              let raw = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { throw RequestError.invalidURL }
        func value(_ key: String) -> String? { parts.queryItems?.first(where: { $0.name == key })?.value }
        var result = PlaybackRequest(url: url, title: value("title") ?? url.lastPathComponent)
        result.contentID = value("id") ?? ""
        result.season = value("season").flatMap(Int.init)
        result.episode = value("episode").flatMap(Int.init)
        result.isAnime = value("anime") == "1" || result.contentID.hasPrefix("mal:") || result.contentID.hasPrefix("kitsu:")
        let start = value("start").flatMap(Double.init) ?? 0
        result.start = start.isFinite ? max(0, start) : 0
        if let raw = value("subtitle"), let sub = URL(string: raw), ["http", "https"].contains(sub.scheme ?? "") {
            result.subtitle = sub
        }
        return result
    }
    enum RequestError: LocalizedError {
        case invalidURL
        var errorDescription: String? { "Bitte eine gültige HTTP(S)-Stream-URL öffnen." }
    }
}
