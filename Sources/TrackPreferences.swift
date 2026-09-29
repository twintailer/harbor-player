import Foundation

struct TrackPreferences: Equatable {
    var audio: String
    var subtitles: String
    var preferForced = true
    static var systemLanguage: String { Locale.current.language.languageCode?.identifier ?? "en" }
    static func load(_ defaults: UserDefaults = .standard) -> Self {
        Self(audio: defaults.string(forKey: "preferredAudio") ?? systemLanguage,
             subtitles: defaults.string(forKey: "preferredSubtitles") ?? systemLanguage,
             preferForced: defaults.object(forKey: "preferForced") as? Bool ?? true)
    }
    static let languages = ["de", "en", "ja", "fr", "es", "it", "pt", "nl", "pl", "ru", "uk", "tr", "ar", "ko", "zh"]
    static func normalized(_ value: String) -> String {
        let base = String(value.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first ?? "")
        let aliases = ["deu": "de", "ger": "de", "eng": "en", "jpn": "ja", "fra": "fr", "fre": "fr", "spa": "es", "ita": "it", "por": "pt", "nld": "nl", "dut": "nl", "pol": "pl", "rus": "ru", "ukr": "uk", "tur": "tr", "ara": "ar", "kor": "ko", "zho": "zh", "chi": "zh"]
        return aliases[base] ?? base
    }
    static func matches(_ track: MPVTrack, language: String) -> Bool {
        normalized(track.lang) == normalized(language) && !language.isEmpty
    }
    static func isForced(_ track: MPVTrack) -> Bool {
        track.forced || track.title.range(of: #"\bforced\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    func preferredAudio(in tracks: [MPVTrack]) -> MPVTrack? {
        tracks.filter { $0.type == "audio" && Self.matches($0, language: audio) }.sorted(by: rank).first
    }
    func preferredSubtitle(in tracks: [MPVTrack], actualAudio: MPVTrack?) -> Int {
        let forced = preferForced && (actualAudio.map { Self.matches($0, language: audio) } == true)
        return tracks.filter { $0.type == "sub" && Self.matches($0, language: subtitles) && Self.isForced($0) == forced }
            .sorted(by: rank).first?.id ?? -1
    }
    private func rank(_ lhs: MPVTrack, _ rhs: MPVTrack) -> Bool {
        if lhs.hearingImpaired != rhs.hearingImpaired { return !lhs.hearingImpaired }
        if lhs.defaultTrack != rhs.defaultTrack { return lhs.defaultTrack }
        if lhs.selected != rhs.selected { return lhs.selected }
        return lhs.id < rhs.id
    }
}
