import SwiftUI

@MainActor
final class PlaybackReturn: ObservableObject {
    @Published var message: String?
    @Published var retryURL: URL?
    @Published var lastCallback: URL?
    private var pending: (PlaybackRequest, Double, Bool)?
    func prepare(_ request: PlaybackRequest, position: Double, loaded: Bool) { pending = (request, position, loaded) }
    func deliverPending() {
        guard let value = pending else { return }; pending = nil
        send(value.0, position: value.1, loaded: value.2)
    }

    func send(_ request: PlaybackRequest, position: Double, loaded: Bool) {
        let preferWeb = UserDefaults.standard.string(forKey: "stremioReturnTarget") == "web"
        guard let url = PlaybackCallback.make(request: request, position: position, loaded: loaded, web: preferWeb) else { return }
        deliver(url, fallback: PlaybackCallback.make(request: request, position: position, loaded: loaded, web: true))
    }

    func retry() { if let url = retryURL { deliver(url, fallback: nil) } }

    private func deliver(_ url: URL, fallback: URL?) {
        lastCallback = url
        #if DEBUG
        if ProcessInfo.processInfo.environment["HARBOR_TEST_CAPTURE_CALLBACK"] == "1" {
            message = "Test-Rückgabe erfasst"; return
        }
        #endif
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard let self else { return }
            if opened {
                self.retryURL = nil
                self.message = "Abspielposition an Stremio übergeben."
            } else if let fallback, fallback != url {
                self.deliver(fallback, fallback: nil)
            } else {
                self.retryURL = url
                self.message = "Stremio konnte nicht geöffnet werden. Die Rückgabe kann erneut versucht werden."
            }
        }
    }
}
