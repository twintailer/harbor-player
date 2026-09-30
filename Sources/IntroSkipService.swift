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
    static var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    private static var resultCache: [String: [SkipSegment]] = [:]
    private static var mappingCache: [String: AnimeMapping] = [:]

    /// A plain filename can still identify a TV episode when it contains SxxExx.
    /// Only exact title matches are accepted; ambiguous names never trigger skips.
    static func identify(_ request: PlaybackRequest) async -> PlaybackRequest {
        var result = request
        result.inferContentIdentity()
        guard result.contentID.isEmpty, result.season != nil, result.episode != nil,
              let range = result.title.range(of: #"(?i)\bS\d{1,3}[ ._-]*E\d{1,4}\b"#, options: .regularExpression) else { return result }
        let title = String(result.title[..<range.lowerBound])
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-")))
        guard title.count >= 2,
              let escaped = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://v3-cinemeta.strem.io/catalog/series/top/search=\(escaped).json"),
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return result }
        let normalize: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        let matches = catalog.metas.filter { normalize($0.name) == normalize(title) && $0.id.hasPrefix("tt") }
        if matches.count == 1 { result.contentID = matches[0].id }
        return result
    }

    struct AnimeEpisode: Equatable {
        let malID: Int
        let episode: Int
        let imdbID: String?
        let season: Int?
        let tvEpisode: Int?
    }

    static func segments(contentID: String, season: Int?, episode: Int?,
                         duration: Double, isAnime: Bool,
                         chapters: [MediaChapter], onUpdate: (([SkipSegment]) -> Void)? = nil) async -> [SkipSegment] {
        guard duration.isFinite, duration > 0, duration < Double(Int.max) / 1000 else { return [] }
        let key = "\(contentID):\(season ?? 0):\(episode ?? 0):\(Int(duration)):\(isAnime)"
        if let cached = resultCache[key] {
            return merge([cached, chapterSegments(chapters, duration: duration)], duration: duration)
        }

        async let introDB = fetchIntroDB(contentID: contentID, season: season,
                                         episode: episode, duration: duration)
        // IMDb anime often arrive without an anime flag. Detect them by mapping
        // the actual season/episode; never choose an arbitrary ARM result.
        async let animeTarget = resolveAnimeEpisode(contentID: contentID, season: season, episode: episode)
        var database = await introDB
        // Recaps can start immediately. Show available TV/chapter timestamps
        // while the additional anime-season mapping is still being resolved.
        if !Task.isCancelled { onUpdate?(merge([database, chapterSegments(chapters, duration: duration)], duration: duration)) }
        let target = await animeTarget
        async let aniSkip = fetchAniSkip(target: target, duration: duration)
        if database.isEmpty, !contentID.hasPrefix("tt"), let target,
           let imdb = target.imdbID, let mappedSeason = target.season, let mappedEpisode = target.tvEpisode {
            database = await fetchIntroDB(contentID: imdb, season: mappedSeason,
                                          episode: mappedEpisode, duration: duration)
        }
        let network = merge([await aniSkip, database], duration: duration)
        // Allow a later user-triggered retry after transient network failures.
        if !network.isEmpty { resultCache[key] = network }
        return merge([network, chapterSegments(chapters, duration: duration)], duration: duration)
    }

    // MARK: - AniSkip

    private static func fetchAniSkip(target: AnimeEpisode?, duration: Double) async -> [SkipSegment] {
        guard let target else { return [] }
        var components = URLComponents(string: "https://api.aniskip.com/v2/skip-times/\(target.malID)/\(target.episode)")!
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

    static func resolveAnimeEpisode(contentID: String, season: Int?, episode: Int?) async -> AnimeEpisode? {
        guard let episode, episode > 0 else { return nil }
        let parts = contentID.split(separator: ":")
        if let provider = parts.first, ["mal", "kitsu", "anilist"].contains(String(provider)),
           parts.count >= 2, let id = Int(parts[1]), id > 0 {
            let mapping = await animeMapping(query: "\(provider)_id=\(id)")
            var malID = mapping?.mappings.malID
            if provider == "mal" { malID = id }
            if malID == nil, provider == "kitsu" { malID = await malIDForKitsu(id) }
            guard let malID else { return nil }
            let mapped = mapping?.episodes[String(episode)]
            return AnimeEpisode(malID: malID, episode: episode, imdbID: mapping?.mappings.imdbID,
                                season: mapped?.seasonNumber, tvEpisode: mapped?.episodeNumber)
        }
        guard let season, season >= 0 else { return nil }
        if contentID.hasPrefix("tt") {
            if let mapping = await animeMapping(query: "imdb_id=\(contentID)"),
               let match = mappedEpisode(mapping, season: season, episode: episode) { return match }
            let ids = await malIDsForIMDb(contentID)
            // IMDb combines multiple MAL seasons/cours. AniZip provides the
            // exact TV episode -> MAL-local episode correspondence for each.
            let matches = await withTaskGroup(of: AnimeEpisode?.self, returning: [AnimeEpisode].self) { group in
                for id in ids.prefix(12) {
                    group.addTask {
                        guard let mapping = await animeMapping(query: "mal_id=\(id)") else { return nil }
                        return await mappedEpisode(mapping, season: season, episode: episode)
                    }
                }
                var matches: [AnimeEpisode] = []
                for await match in group { if let match, !matches.contains(match) { matches.append(match) } }
                return matches
            }
            return matches.count == 1 ? matches[0] : nil
        }
        if contentID.hasPrefix("tmdb:tv:"), let id = parts.last,
           let mapping = await animeMapping(query: "themoviedb_id=\(id)") {
            return mappedEpisode(mapping, season: season, episode: episode)
        }
        return nil
    }

    private static func animeMapping(query: String) async -> AnimeMapping? {
        if let cached = mappingCache[query] { return cached }
        guard let url = URL(string: "https://api.ani.zip/mappings?\(query)"),
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let mapping = try? JSONDecoder().decode(AnimeMapping.self, from: data) else { return nil }
        mappingCache[query] = mapping
        return mapping
    }

    private static func mappedEpisode(_ mapping: AnimeMapping, season: Int, episode: Int) -> AnimeEpisode? {
        guard let malID = mapping.mappings.malID else { return nil }
        let matches = mapping.episodes.filter {
            Int($0.key) != nil && $0.value.seasonNumber == season && $0.value.episodeNumber == episode
        }
        guard matches.count == 1, let match = matches.first, let local = Int(match.key), local > 0 else { return nil }
        return AnimeEpisode(malID: malID, episode: local, imdbID: mapping.mappings.imdbID,
                            season: season, tvEpisode: episode)
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

    private static func malIDsForIMDb(_ imdbID: String) async -> [Int] {
        var components = URLComponents(string: "https://arm.haglund.dev/api/v2/imdb")!
        components.queryItems = [
            URLQueryItem(name: "id", value: imdbID),
            URLQueryItem(name: "include", value: "myanimelist"),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let entries = try? JSONDecoder().decode([ARMEntry].self, from: data) else { return [] }
        return Array(Set(entries.compactMap(\.myanimelist))).sorted()
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
        query.append(.init(name: "duration_ms", value: String(Int((duration * 1000).rounded()))))
        var components = URLComponents(string: "https://api.theintrodb.org/v3/media")!
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

    static func chapterSegments(_ chapters: [MediaChapter], duration: Double) -> [SkipSegment] {
        chapters.compactMap { chapter in
            let title = chapter.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: SkipSegment.Kind?
            if ["op", "ncop", "opening", "intro"].contains(title)
                || ["intro", "opening", "theme song"].contains(where: { title.contains($0) }) {
                kind = .intro
            } else if ["recap", "previously", "rückblick"].contains(where: { title.contains($0) }) {
                kind = .recap
            } else if chapter.start > duration * 0.5
                        && (title == "ed" || title == "nced" || ["ending", "outro", "credit", "closing", "abspann"].contains(where: { title.contains($0) })) {
                kind = .outro
            } else {
                kind = nil
            }
            guard let kind, chapter.end > chapter.start else { return nil }
            return SkipSegment(kind: kind, start: chapter.start, end: chapter.end, source: .chapters)
        }
    }

    static func merge(_ lists: [[SkipSegment]], duration: Double) -> [SkipSegment] {
        var merged: [SkipSegment] = []
        for segment in lists.flatMap({ $0 }) {
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
        return merged.sorted { $0.start < $1.start }
    }

    private struct AniSkipResponse: Decodable { let found: Bool; let results: [AniSkipResult]? }
    private struct AniSkipResult: Decodable { let interval: AniSkipInterval; let skipType: String }
    private struct AniSkipInterval: Decodable { let startTime: Double; let endTime: Double }
    private struct ARMEntry: Decodable { let myanimelist: Int? }
    private struct Catalog: Decodable { let metas: [CatalogMeta] }
    private struct CatalogMeta: Decodable { let id: String; let name: String }
    private struct AnimeMapping: Decodable {
        let mappings: AnimeIDs
        let episodes: [String: AnimeMappedEpisode]
    }
    private struct AnimeIDs: Decodable {
        let malID: Int?
        let imdbID: String?
        enum CodingKeys: String, CodingKey { case malID = "mal_id", imdbID = "imdb_id" }
    }
    private struct AnimeMappedEpisode: Decodable {
        let seasonNumber: Int?
        let episodeNumber: Int?
    }
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
