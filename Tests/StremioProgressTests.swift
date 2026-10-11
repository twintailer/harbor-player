import Foundation

@main struct StremioProgressTests {
    static func main() throws {
        let request = try PlaybackRequest.parse(URL(string: "infuse://x-callback-url/play?url=https%3A%2F%2Fexample.org%2Fvideo.mkv&x-success=stremio%3A%2F%2F%2Fdetail%2Fseries%2Ftt123%2Ftt123%3A1%3A2")!)
        precondition(!request.startSupplied && request.progressVideoID == "tt123:1:2")
        func record(_ id: String = "tt123:1:2", offset: Double = 1234000, duration: Double = 2400000) -> [String: Any] {
            ["_id": "tt123", "state": ["video_id": id, "timeOffset": offset, "duration": duration]]
        }
        precondition(StremioProgress.seconds(record: record(), request: request) == 1234)
        precondition(StremioProgress.seconds(record: record("tt123:1:1"), request: request) == nil)
        for offset in [0, -1, Double.nan, Double.infinity, 315_576_000_001, 2400000] {
            precondition(StremioProgress.seconds(record: record(offset: offset), request: request) == nil)
        }
        let zero = try PlaybackRequest.parse(URL(string: requestLink(request) + "&position=0")!)
        precondition(zero.startSupplied && zero.start == 0)
        let invalid = try PlaybackRequest.parse(URL(string: requestLink(request) + "&position=nan")!)
        precondition(!invalid.startSupplied)
        let movie = PlaybackRequest(url: request.url, title: "Movie", contentID: "tt123", contentType: "movie")
        precondition(movie.progressVideoID == "tt123")
        print("Stremio progress tests passed")
    }
    static func requestLink(_ request: PlaybackRequest) -> String {
        "infuse://x-callback-url/play?url=https%3A%2F%2Fexample.org%2Fvideo.mkv&x-success=stremio%3A%2F%2F%2Fdetail%2Fseries%2Ftt123%2Ftt123%3A1%3A2"
    }
}
