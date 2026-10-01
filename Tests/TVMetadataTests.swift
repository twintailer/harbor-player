import Foundation

@main struct TVMetadataTests {
    @MainActor static func main() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MetadataFixture.self]
        TVMetadataService.session = URLSession(configuration: config)
        var request = PlaybackRequest(url: URL(string: "https://example.org/private.mkv?token=secret")!, title: "Pokemon.S01E44.German.DVDRip.mkv", contentID: "tt0168366", season: 1, episode: 44)
        var partial = ""
        let localized = await TVMetadataService.title(for: request, language: "de-DE") { partial = $0 }
        precondition(localized == "Die Paras Problematik – (1×44)")
        precondition(partial == "The Problem with Paras – (1×44)")
        request.contentID = "tt2"
        let fallback = await TVMetadataService.title(for: request, language: "de-DE")
        precondition(fallback == "The Problem with Paras – (1×44)", "Provider failure falls back to the exact Cinemeta episode")
        request.episode = 999
        let missing = await TVMetadataService.title(for: request, language: "de-DE")
        precondition(missing == nil, "Never display another episode or the show title as an episode name")
        request.contentID = "mal:1"
        let unsupported = await TVMetadataService.title(for: request, language: "de-DE")
        precondition(unsupported == nil)
        request.episode = 44
        precondition(TVMetadataService.fallback(request) == "Pokemon – (1×44)")
        print("Localized episode names, provider fallback, missing episodes and filename display tests passed")
    }
}
private final class MetadataFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        precondition(!url.absoluteString.contains("secret") && !url.absoluteString.contains("private.mkv"), "Metadata requests must not send stream tokens")
        let localized = url.host != "v3-cinemeta.strem.io"
        let status = localized && url.lastPathComponent == "tt2.json" ? 503 : 200
        let title = localized ? "Die Paras Problematik" : "The Problem with Paras"
        let json = "{\"meta\":{\"name\":\"Pokémon\",\"videos\":[{\"title\":\"\(title)\",\"season\":1,\"episode\":44},{\"name\":\"Wrong episode\",\"season\":1,\"episode\":43}]}}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
