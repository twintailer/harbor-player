import Foundation

extension PlaybackRequest {
    var progressVideoID: String? {
        guard !contentID.isEmpty else { return nil }
        if let callback = successCallback, let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false) {
            let path = parts.scheme == "https" ? parts.fragment.flatMap { URLComponents(string: $0)?.path } ?? parts.path : parts.path
            let fields = path.split(separator: "/").map(String.init)
            if let index = fields.firstIndex(of: "detail"), fields.count > index + 3, fields[index + 2] == contentID {
                return fields[index + 3]
            }
        }
        if contentType == "movie" { return contentID }
        if let season, let episode { return "\(contentID):\(season):\(episode)" }
        return nil
    }
}

enum StremioProgress {
    /// Datastore offsets are milliseconds; the Infuse link and mpv use seconds.
    static func seconds(record: [String: Any], request: PlaybackRequest) -> Double? {
        guard record["_id"] as? String == request.contentID,
              let videoID = request.progressVideoID,
              let state = record["state"] as? [String: Any],
              state["video_id"] as? String == videoID,
              let offset = (state["timeOffset"] as? NSNumber)?.doubleValue,
              offset.isFinite, offset > 0, offset <= 315_576_000_000 else { return nil }
        if let duration = (state["duration"] as? NSNumber)?.doubleValue, duration > 0, offset >= duration { return nil }
        return offset / 1000
    }
}
