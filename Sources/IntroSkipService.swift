import Foundation

struct SkipSegment: Hashable, Identifiable {
    enum Kind: String { case intro, recap, outro }
    enum Source: String { case aniSkip, introDB, chapters }

    let kind: Kind
    let start: Double
    let end: Double
    let source: Source
    var id: String { "\(kind.rawValue):\(Int(start * 10)):\(Int(end * 10))" }

    var label: String {
        switch kind {
        case .intro: return "Skip Intro"
        case .recap: return "Skip Recap"
        case .outro: return "Skip Credits"
        }
    }
}

/// Mirrors Harbor desktop's skip-source order: AniSkip, TheIntroDB, then named
/// chapters carried by the file. Network providers are public and need no key.
@MainActor
enum IntroSkipService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    private static var resultCache: [String: [SkipSegment]] = [:]
    private static var malCache: [String: Int?] = [:]

    static func segments(contentID: String, season: Int?, episode: Int?,
                         duration: Double, isAnime: Bool,
                         chapters: [MediaChapter]) async -> [SkipSegment] {
        guard duration.isFinite, duration > 0, duration < Double(Int.max) / 1000 else { return [] }
        let key = "\(contentID):\(season ?? 0):\(episode ?? 0):\(Int(duration))"
        if let cached = resultCache[key] {
            return merge([cached, chapterSegments(chapters, duration: duration)], duration: duration)
        }

        async let introDB = fetchIntroDB(contentID: contentID, season: season,
                                         episode: episode, duration: duration)
        async let aniSkip = fetchAniSkip(contentID: contentID, season: season,
                                         episode: episode, duration: duration,
                                         enabled: isAnime)
        let network = merge([await aniSkip, await introDB], duration: duration)
        resultCache[key] = network
        return merge([network, chapterSegments(chapters, duration: duration)], duration: duration)
    }

    // MARK: - AniSkip

    private static func fetchAniSkip(contentID: String, season: Int?, episode: Int?,
                                     duration: Double, enabled: Bool) async -> [SkipSegment] {
        guard enabled, let episode, episode > 0,
              let malID = await resolveMALID(contentID: contentID, season: season ?? 1) else { return [] }
        var components = URLComponents(string: "https://api.aniskip.com/v2/skip-times/\(malID)/\(episode)")!
        components.queryItems = ["op", "ed", "mixed-op", "mixed-ed", "recap"].map {
            URLQueryItem(name: "types[]", value: $0)
        } + [URLQueryItem(name: "episodeLength", value: String(Int(duration.rounded())))]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(AniSkipResponse.self, from: data),
              decoded.found else { return [] }
        return (decoded.results ?? []).compactMap { item in
            let type = item.skipType.lowercased()
            let kind: SkipSegment.Kind = type == "ed" || type == "mixed-ed"
                ? .outro : (type == "recap" ? .recap : .intro)
            guard item.interval.endTime > item.interval.startTime else { return nil }
            return SkipSegment(kind: kind, start: item.interval.startTime,
                               end: item.interval.endTime, source: .aniSkip)
        }
    }

    private static func resolveMALID(contentID: String, season: Int) async -> Int? {
        let cacheKey = "\(contentID):\(season)"
        if let cached = malCache[cacheKey] { return cached }
        let result: Int?
        if contentID.hasPrefix("mal:") {
            result = contentID.dropFirst(4).split(separator: ":").first.flatMap { Int($0) }
        } else if contentID.hasPrefix("kitsu:") {
            let value = contentID.dropFirst(6).split(separator: ":").first.flatMap { Int($0) }
            if let kitsuID = value {
                result = await malIDForKitsu(kitsuID)
            } else {
                result = nil
            }
        } else if contentID.hasPrefix("tt") {
            result = await malIDForIMDb(contentID, season: season)
        } else {
            result = nil
        }
        malCache[cacheKey] = result
        return result
    }

    private static func malIDForKitsu(_ kitsuID: Int) async -> Int? {
        guard let url = URL(string: "https://kitsu.io/api/edge/anime/\(kitsuID)/mappings"),
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(KitsuMappings.self, from: data) else { return nil }
        return decoded.data.first(where: {
            $0.attributes.externalSite.lowercased() == "myanimelist/anime"
        }).flatMap { Int($0.attributes.externalID) }
    }

    private static func malIDForIMDb(_ imdbID: String, season: Int) async -> Int? {
        var components = URLComponents(string: "https://arm.haglund.dev/api/v2/imdb")!
        components.queryItems = [
            URLQueryItem(name: "id", value: imdbID),
            URLQueryItem(name: "include", value: "myanimelist"),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let entries = try? JSONDecoder().decode([ARMEntry].self, from: data) else { return nil }
        let ids = entries.compactMap(\.myanimelist)
        guard !ids.isEmpty else { return nil }
        return ids.indices.contains(max(0, season - 1)) ? ids[max(0, season - 1)] : ids[0]
    }

    // MARK: - TheIntroDB

    private static func fetchIntroDB(contentID: String, season: Int?, episode: Int?,
                                     duration: Double) async -> [SkipSegment] {
        var query: [URLQueryItem] = []
        if contentID.hasPrefix("tmdb:movie:") {
            query.append(.init(name: "tmdb_id", value: String(contentID.dropFirst("tmdb:movie:".count))))
        } else if contentID.hasPrefix("tmdb:tv:") {
            query.append(.init(name: "tmdb_id", value: String(contentID.dropFirst("tmdb:tv:".count))))
        } else if contentID.hasPrefix("tt") {
            query.append(.init(name: "imdb_id", value: contentID))
        } else {
            return []
        }
        if let season, let episode {
            query.append(.init(name: "season", value: String(season)))
            query.append(.init(name: "episode", value: String(episode)))
        }
        var components = URLComponents(string: "https://api.theintrodb.org/v2/media")!
        components.queryItems = query
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(IntroDBResponse.self, from: data) else { return [] }
        return spans(decoded.intro, kind: .intro, duration: duration)
            + spans(decoded.recap, kind: .recap, duration: duration)
            + spans(decoded.credits, kind: .outro, duration: duration)
            + spans(decoded.preview, kind: .outro, duration: duration)
    }

    private static func spans(_ values: [IntroDBSpan]?, kind: SkipSegment.Kind,
                              duration: Double) -> [SkipSegment] {
        (values ?? []).compactMap { span in
            let start = Double(span.startMS ?? 0) / 1000
            let end = Double(span.endMS ?? Int(duration * 1000)) / 1000
            guard end > start else { return nil }
            return SkipSegment(kind: kind, start: start, end: end, source: .introDB)
        }
    }

    // MARK: - Chapters / merge

    private static func chapterSegments(_ chapters: [MediaChapter], duration: Double) -> [SkipSegment] {
        chapters.compactMap { chapter in
            let title = chapter.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: SkipSegment.Kind?
            if ["op", "ncop", "opening", "intro"].contains(title)
                || ["intro", "opening", "theme song"].contains(where: { title.contains($0) }) {
                kind = .intro
            } else if ["recap", "previously", "cold open", "prologue", "avant", "teaser"].contains(where: { title.contains($0) }) {
                kind = .recap
            } else if chapter.start > duration * 0.5
                        && (["ed", "ending", "outro", "credit", "closing"].contains(where: { title.contains($0) })) {
                kind = .outro
            } else {
                kind = nil
            }
            guard let kind, chapter.end > chapter.start else { return nil }
            return SkipSegment(kind: kind, start: chapter.start, end: chapter.end, source: .chapters)
        }
    }

    private static func merge(_ lists: [[SkipSegment]], duration: Double) -> [SkipSegment] {
        var merged: [SkipSegment] = []
        for segment in lists.flatMap({ $0 }).sorted(by: { $0.start < $1.start }) {
            guard segment.start.isFinite, segment.end.isFinite else { continue }
            let end = duration > 0 ? min(segment.end, duration) : segment.end
            let normalized = SkipSegment(kind: segment.kind, start: max(0, segment.start),
                                         end: end, source: segment.source)
            let length = normalized.end - normalized.start
            guard length >= 2, length <= 360,
                  normalized.kind != .outro || duration <= 0 || normalized.start >= duration * 0.5,
                  !merged.contains(where: { normalized.start < $0.end && normalized.end > $0.start }) else { continue }
            merged.append(normalized)
        }
        return merged
    }

    private struct AniSkipResponse: Decodable { let found: Bool; let results: [AniSkipResult]? }
    private struct AniSkipResult: Decodable { let interval: AniSkipInterval; let skipType: String }
    private struct AniSkipInterval: Decodable { let startTime: Double; let endTime: Double }
    private struct ARMEntry: Decodable { let myanimelist: Int? }
    private struct KitsuMappings: Decodable { let data: [KitsuMapping] }
    private struct KitsuMapping: Decodable { let attributes: KitsuMappingAttributes }
    private struct KitsuMappingAttributes: Decodable {
        let externalSite: String
        let externalID: String
        enum CodingKeys: String, CodingKey { case externalSite, externalID = "externalId" }
    }
    private struct IntroDBResponse: Decodable {
        let intro: [IntroDBSpan]?
        let recap: [IntroDBSpan]?
        let credits: [IntroDBSpan]?
        let preview: [IntroDBSpan]?
    }
    private struct IntroDBSpan: Decodable {
        let startMS: Int?
        let endMS: Int?
        enum CodingKeys: String, CodingKey { case startMS = "start_ms", endMS = "end_ms" }
    }
}
