import SwiftUI
import AVKit

/// Native video handoff is separate from mpv: AirPlay cannot send its Metal output.
@MainActor final class AirPlaySession: ObservableObject {
    struct Position {
        var seconds: Double
        var paused: Bool
        var speed: Double
    }
    @Published private(set) var player: AVPlayer?
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    @Published private(set) var external = false
    @Published private(set) var position = 0.0
    @Published private(set) var paused = true
    private var prepare: Task<Void, Never>?
    private var statusObserver: NSKeyValueObservation?
    private var routeObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var transferred: Position?
    private var seekFinished = false
    private var generation = UUID()

    func start(_ url: URL, takePosition: @escaping () -> Position) {
        guard !loading, player == nil else { return }
        loading = true; message = nil
        let token = generation
        prepare = Task { @MainActor in
            do {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable) else { throw NativeError.unsupported }
                guard !Task.isCancelled, token == generation else { return }
                let item = AVPlayerItem(asset: asset)
                let native = AVPlayer(playerItem: item)
                native.allowsExternalPlayback = true
                native.usesExternalPlaybackWhileExternalScreenIsActive = true
                player = native
                statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    let status = item.status
                    Task { @MainActor [weak self] in
                        guard let self, token == self.generation, self.player === native else { return }
                        if status == .failed {
                            self.loading = false
                            self.message = "Der Systemplayer kann diesen Stream nicht wiedergeben. Schließe AirPlay, um in Kairo weiterzusehen, oder nutze die Bildschirmsynchronisierung."
                        } else if status == .readyToPlay, self.transferred == nil {
                            do {
                                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
                                try AVAudioSession.sharedInstance().setActive(true)
                            } catch {
                                self.loading = false; self.message = "Die AirPlay-Audioausgabe konnte nicht aktiviert werden."
                                return
                            }
                            let start = takePosition()
                            self.transferred = start; self.position = start.seconds; self.paused = start.paused
                            native.seek(to: CMTime(seconds: max(0, start.seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                                Task { @MainActor [weak self] in
                                    guard let self, token == self.generation, self.player === native else { return }
                                    self.seekFinished = finished; self.loading = false
                                    if !finished { self.message = "Die Abspielposition konnte nicht übernommen werden. Schließe AirPlay und versuche es erneut."; return }
                                    if !start.paused { native.playImmediately(atRate: Float(start.speed)) }
                                }
                            }
                        }
                    }
                }
                routeObserver = native.observe(\.isExternalPlaybackActive, options: [.initial, .new]) { [weak self] value, _ in
                    let active = value.isExternalPlaybackActive
                    Task { @MainActor [weak self] in if self?.generation == token { self?.external = active } }
                }
                timeObserver = native.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                    Task { @MainActor [weak self] in
                        guard let self, token == self.generation, self.seekFinished else { return }
                        if time.seconds.isFinite { self.position = max(0, time.seconds) }
                        self.paused = native.timeControlStatus == .paused
                    }
                }
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                loading = false
                // Never include a private stream URL or server token in an error.
                message = "Dieser Stream ist mit Video-AirPlay nicht kompatibel oder nicht erreichbar. Nutze für MKV die Bildschirmsynchronisierung."
            }
        }
    }

    @discardableResult func finish() -> Position? {
        var result = transferred
        if seekFinished, let native = player {
            let seconds = native.currentTime().seconds
            if seconds.isFinite && seconds >= 0 { result?.seconds = seconds }
            result?.paused = native.timeControlStatus == .paused
            if native.rate > 0 { result?.speed = Double(native.rate) }
        }
        generation = UUID(); prepare?.cancel(); prepare = nil
        statusObserver = nil; routeObserver = nil
        if let timeObserver, let native = player { native.removeTimeObserver(timeObserver) }
        timeObserver = nil; player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        transferred = nil; seekFinished = false; loading = false; external = false; message = nil
        return result
    }
    private enum NativeError: Error { case unsupported }
}

struct AirPlayScreen: View {
    @ObservedObject var session: AirPlaySession
    let request: PlaybackRequest
    let takePosition: () -> AirPlaySession.Position

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: session.external ? "airplay.video" : "airplay.audio")
                Text(session.player == nil ? "AirPlay-Audio auswählen" : (session.external ? "Video über AirPlay" : "AirPlay-Gerät auswählen"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                AirPlayRoutePicker(video: session.player != nil).frame(width: 44, height: 44)
                    .accessibilityIdentifier("airPlayRoutePicker")
            }
            if let player = session.player, session.message == nil {
                NativeAirPlayPlayer(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
                #if DEBUG
                if ProcessInfo.processInfo.environment["HARBOR_TEST_CAPTURE_CALLBACK"] == "1" {
                    Text("\(Int(session.position))|\(session.paused ? "paused" : "playing")")
                        .font(.caption).accessibilityIdentifier("airPlayPlaybackDiagnostics")
                }
                #endif
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let message = session.message { Text(message).accessibilityIdentifier("airPlayError") }
                        else {
                            Button {
                                session.start(request.url, takePosition: takePosition)
                            } label: { Label("Video im AirPlay-Systemplayer öffnen", systemImage: "airplay.video") }
                                .buttonStyle(.borderedProminent).disabled(session.loading).accessibilityIdentifier("startVideoAirPlay")
                            Text("Für kompatible Streams, etwa MP4 oder HLS. Danach oben das AirPlay-Gerät auswählen. Die aktuelle Abspielposition wird übernommen.")
                        }
                        Text("Anime4K, Kairo-Untertitelstil und Skip Intro sind im Systemplayer nicht verfügbar. Dessen Audio- und Untertitelspuren wählst du direkt in seinen Bedienelementen.")
                        Label("Für MKV oder Anime4K: Kontrollzentrum öffnen → Bildschirmsynchronisierung → Fernseher auswählen. Danach AirPlay hier schließen und in Kairo weitersehen.", systemImage: "rectangle.on.rectangle")
                            .accessibilityIdentifier("airPlayMirroringHelp")
                        Text("Der Fernseher muss AirPlay unterstützen und den Stream erreichen können. Google Chromecast wird hier nicht unterstützt.")
                    }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if session.loading { ProgressView("Stream prüfen …") }
        }.padding(16).background(.black)
    }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    let video: Bool
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white; view.activeTintColor = .systemBlue
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.prioritizesVideoDevices = video
    }
}

private struct NativeAirPlayPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player; controller.allowsPictureInPicturePlayback = false
        controller.entersFullScreenWhenPlaybackBegins = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player = nil }
}
