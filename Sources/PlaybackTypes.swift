import Foundation

struct MPVTrack: Identifiable, Hashable {
    let id: Int
    let type: String
    let title: String
    let lang: String
    let selected: Bool
    let external: Bool
    let forced: Bool
    let defaultTrack: Bool
    let hearingImpaired: Bool
    let codec: String
    let externalFilename: String
}

struct MediaChapter: Hashable {
    let title: String
    let start: Double
    let end: Double
}
