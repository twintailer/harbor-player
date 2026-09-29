import SwiftUI
import AVFoundation
import Libmpv

@MainActor
final class PlayerState: ObservableObject {
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var paused = false
    @Published var buffering = true
    @Published var tracks: [MPVTrack] = []
    @Published var chapters: [MediaChapter] = []
    @Published var error: String?
    @Published var animeActive = false
    @Published var speed = 1.0
    @Published var segments: [SkipSegment] = []
    @Published var skipStatus = "Kapitel werden geladen …"
    weak var controller: PlayerController?
    func toggle() { controller?.command(["cycle", "pause"]) }
    func seek(_ seconds: Double) { controller?.command(["seek", String(max(0, min(duration, seconds))), "absolute+exact"]) }
    func skip(_ seconds: Double) { seek(position + seconds) }
    func rate(_ value: Double) { speed = value; controller?.property("speed", String(value)) }
    var currentSegment: SkipSegment? { segments.first { position >= $0.start && position < $0.end } }
}

struct VideoSurface: UIViewControllerRepresentable {
    let request: PlaybackRequest
    @ObservedObject var state: PlayerState
    func makeUIViewController(context: Context) -> PlayerController {
        let controller = PlayerController(request: request, state: state)
        state.controller = controller
        return controller
    }
    func updateUIViewController(_ controller: PlayerController, context: Context) {}
    static func dismantleUIViewController(_ controller: PlayerController, coordinator: ()) { controller.shutdown() }
}

// The queue owns every native access after initialization, including destruction.
// Teardown retains the Metal layer until the renderer has joined its threads.
final class PlayerController: UIViewController {
    private let request: PlaybackRequest
    private weak var state: PlayerState?
    private let queue = DispatchQueue(label: "app.harbor.player.mpv")
    private var handle: OpaquePointer?
    private var metal: CAMetalLayer?
    private var timer: DispatchSourceTimer?
    private var stopping = false
    private var shutdownFinished = false
    private var shutdownCallbacks: [() -> Void] = []
    private var tick = 0
    private var loaded = false // queue-owned; failed opens must not reset Stremio progress
    private var preferences = TrackPreferences.load()
    private var manualAudio = false
    private var manualSubtitles = false
    init(request: PlaybackRequest, state: PlayerState) {
        self.request = request; self.state = state
        self.manualSubtitles = request.subtitle != nil
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        PlaybackOrientation.setPlaying(true, in: view.window?.windowScene)
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = VideoMetalLayer()
        layer.frame = view.bounds
        layer.contentsScale = UIScreen.main.scale
        layer.drawableSize = CGSize(width: max(1, view.bounds.width * UIScreen.main.scale), height: max(1, view.bounds.height * UIScreen.main.scale))
        layer.framebufferOnly = true
        view.layer.addSublayer(layer); metal = layer
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { state?.error = "Audio konnte nicht aktiviert werden: \(error.localizedDescription)" }
        guard let mpv = mpv_create() else { state?.error = "Player konnte nicht gestartet werden."; return }
        handle = mpv
        #if DEBUG
        mpv_request_log_messages(mpv, "warn")
        #endif
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &wid)
        mpv_set_option_string(mpv, "profile", "fast")
        let options = ["vo": "gpu-next", "gpu-api": "vulkan", "gpu-context": "moltenvk",
                       "hwdec": "videotoolbox-copy", "ao": "audiounit",
                       "vulkan-swap-mode": "fifo", "vd-lavc-threads": "4",
                       "keep-open": "yes", "idle": "yes", "cache": "yes",
                       "demuxer-max-bytes": "96MiB", "demuxer-max-back-bytes": "12MiB",
                       "network-timeout": "30", "subs-match-os-language": "yes",
                       "subs-fallback": "yes", "start": String(request.start)]
        for (key, value) in options { mpv_set_option_string(mpv, key, value) }
        mpv_set_option_string(mpv, "sub-fonts-dir", FontStore.directory.path)
        for (key, value) in SubtitleSettings.load().options { mpv_set_option_string(mpv, key, value) }
        let result = mpv_initialize(mpv)
        diagnostic("initialize=\(result) surface=\(layer.drawableSize) start=\(request.start)")
        guard result >= 0 else {
            state?.error = "Player-Start fehlgeschlagen: \(String(cString: mpv_error_string(result)))"
            handle = nil; mpv_terminate_destroy(mpv); return
        }
        command(["loadfile", request.url.absoluteString])
        let poll = DispatchSource.makeTimerSource(queue: queue)
        poll.schedule(deadline: .now(), repeating: .milliseconds(250))
        poll.setEventHandler { [weak self] in self?.poll() }
        poll.resume(); timer = poll
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !stopping, view.bounds.width > 0, view.bounds.height > 0 else { return }
        let size = CGSize(width: view.bounds.width * UIScreen.main.scale, height: view.bounds.height * UIScreen.main.scale)
        guard metal?.drawableSize != size || metal?.frame != view.bounds else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        metal?.frame = view.bounds
        metal?.drawableSize = size
        CATransaction.commit()
    }
    func command(_ arguments: [String]) {
        queue.async { [weak self] in self?.send(arguments) }
    }
    private func send(_ arguments: [String]) {
        guard let handle else { return }
        let owned = arguments.map { strdup($0) }
        defer { owned.forEach { free($0) } }
        var pointers = owned.map { UnsafePointer($0) }; pointers.append(nil)
        let result = pointers.withUnsafeMutableBufferPointer { mpv_command(handle, $0.baseAddress) }
        diagnostic("command \(arguments.first ?? ""): \(result)")
        if result < 0 {
            let message = String(cString: mpv_error_string(result))
            DispatchQueue.main.async { [weak self] in self?.state?.error = "Player-Befehl fehlgeschlagen: \(message)" }
        }
    }
    func property(_ name: String, _ value: String) {
        queue.async { [weak self] in
            guard let handle = self?.handle else { return }
            mpv_set_property_string(handle, name, value)
        }
    }
    func style(_ style: SubtitleSettings) {
        style.save()
        for (key, value) in style.options { property(key, value) }
    }
    func selectTrack(_ type: String, id: Int) {
        queue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            if type == "audio" { self.manualAudio = true } else { self.manualSubtitles = true }
            mpv_set_property_string(handle, type == "audio" ? "aid" : "sid", id < 0 ? "no" : String(id))
        }
    }
    func addSubtitle(_ path: String) {
        queue.async { [weak self] in self?.manualSubtitles = true; self?.send(["sub-add", path, "select"]) }
    }
    func applyLanguagePreferences() {
        let value = TrackPreferences.load()
        queue.async { [weak self] in self?.preferences = value; self?.manualAudio = false; self?.manualSubtitles = false }
    }
    private func autoSelect(_ tracks: [MPVTrack]) {
        guard let handle else { return }
        var audio = tracks.first { $0.type == "audio" && $0.selected }
        if !manualAudio, let preferred = preferences.preferredAudio(in: tracks), preferred.id != audio?.id {
            if mpv_set_property_string(handle, "aid", String(preferred.id)) >= 0 { audio = preferred }
        }
        if !manualSubtitles {
            let desired = preferences.preferredSubtitle(in: tracks, actualAudio: audio)
            let selected = tracks.first { $0.type == "sub" && $0.selected }?.id ?? -1
            if desired != selected { mpv_set_property_string(handle, "sid", desired < 0 ? "no" : String(desired)) }
        }
    }
    func finishPlayback(_ completion: @escaping (Double, Bool) -> Void) {
        queue.async { [self] in
            var position = 0.0
            let valid: Bool
            if let handle {
                mpv_set_property_string(handle, "pause", "yes")
                valid = loaded && mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position) >= 0 && position.isFinite && position >= 0
            } else { valid = false }
            let snapshot = position
            DispatchQueue.main.async { [self] in shutdown { completion(snapshot, valid) } }
        }
    }
    func anime(_ preset: String) {
        let names: [String]
        switch preset {
        case "fast": names = ["Anime4K_Upscale_DTD_x2"]
        case "A": names = ["Anime4K_Restore_CNN_S", "Anime4K_Upscale_CNN_x2_S"]
        case "B": names = ["Anime4K_Restore_CNN_Soft_S", "Anime4K_Upscale_CNN_x2_S"]
        case "C": names = ["Anime4K_Upscale_Denoise_CNN_x2_S"]
        case "hq": names = ["Anime4K_Clamp_Highlights", "Anime4K_Restore_CNN_VL", "Anime4K_Upscale_CNN_x2_VL", "Anime4K_AutoDownscalePre_x2", "Anime4K_AutoDownscalePre_x4", "Anime4K_Upscale_CNN_x2_M"]
        default: names = []
        }
        let paths = names.compactMap { Bundle.main.url(forResource: $0, withExtension: "glsl", subdirectory: "Anime4K")?.path }
        guard names.count == paths.count else { state?.error = "Anime4K-Dateien fehlen."; return }
        queue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            let result = mpv_set_property_string(handle, "glsl-shaders", paths.joined(separator: ":"))
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopping else { return }
                self.state?.animeActive = result >= 0 && !paths.isEmpty
                if result < 0 { self.state?.error = "Anime4K konnte nicht aktiviert werden." }
            }
        }
    }
    private func number(_ key: String) -> Double {
        guard let handle else { return 0 }
        var value = 0.0
        mpv_get_property(handle, key, MPV_FORMAT_DOUBLE, &value)
        return value.isFinite ? value : 0
    }
    private func string(_ key: String) -> String {
        guard let handle, let value = mpv_get_property_string(handle, key) else { return "" }
        defer { mpv_free(value) }; return String(cString: value)
    }
    private func poll() {
        guard let handle else { return }
        var error: String?
        for _ in 0..<128 {
            guard let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE else { break }
            #if DEBUG
            if event.pointee.event_id == MPV_EVENT_LOG_MESSAGE, let data = event.pointee.data {
                let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                diagnostic("\(String(cString: message.prefix)): \(String(cString: message.text))")
            }
            #endif
            if event.pointee.event_id == MPV_EVENT_FILE_LOADED {
                loaded = true
                if let subtitle = request.subtitle { send(["sub-add", subtitle.absoluteString, "select"]) }
            }
            if event.pointee.event_id == MPV_EVENT_END_FILE, let data = event.pointee.data {
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.error < 0 { error = "Stream konnte nicht abgespielt werden: \(String(cString: mpv_error_string(end.error)))" }
            }
        }
        let position = number("time-pos"), duration = number("duration")
        let paused = string("pause") == "yes", buffering = string("paused-for-cache") == "yes" || string("idle-active") == "yes"
        tick += 1
        if tick % 16 == 0 { diagnostic("position=\(position) duration=\(duration) vo=\(string("current-vo")) video=\(string("video-format"))") }
        var tracks: [MPVTrack]?; var chapters: [MediaChapter]?
        if tick % 4 == 0 {
            tracks = (0..<min(200, max(0, Int(number("track-list/count"))))).map { index in
                let base = "track-list/\(index)"
                return MPVTrack(id: Int(number("\(base)/id")), type: string("\(base)/type"), title: string("\(base)/title"), lang: string("\(base)/lang"), selected: string("\(base)/selected") == "yes", external: string("\(base)/external") == "yes", forced: string("\(base)/forced") == "yes", defaultTrack: string("\(base)/default") == "yes", hearingImpaired: string("\(base)/hearing-impaired") == "yes", codec: string("\(base)/codec"), externalFilename: "")
            }
            if let tracks { autoSelect(tracks) }
            let count = min(500, max(0, Int(number("chapter-list/count"))))
            chapters = (0..<count).map { index in
                MediaChapter(title: string("chapter-list/\(index)/title"), start: number("chapter-list/\(index)/time"), end: index + 1 < count ? number("chapter-list/\(index + 1)/time") : duration)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopping, let state = self.state else { return }
            state.position = position; state.duration = duration; state.paused = paused; state.buffering = buffering
            if let tracks, tracks != state.tracks { state.tracks = tracks }
            if let chapters, chapters != state.chapters { state.chapters = chapters }
            if let error { state.error = error }
        }
    }
    func shutdown(completion: @escaping () -> Void = {}) {
        if shutdownFinished { completion(); return }
        shutdownCallbacks.append(completion)
        guard !stopping else { return }; stopping = true
        timer?.cancel(); timer = nil
        state?.controller = nil
        queue.async { [self] in
            if let handle { self.handle = nil; mpv_terminate_destroy(handle) }
            DispatchQueue.main.async { [self] in
                metal?.removeFromSuperlayer(); metal = nil
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                shutdownFinished = true
                let callbacks = shutdownCallbacks; shutdownCallbacks = []
                callbacks.forEach { $0() }
            }
        }
    }
    private func diagnostic(_ text: String) {
        #if DEBUG
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-mpv.log")
        let data = Data((text + "\n").utf8)
        if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url) }
        else if let file = try? FileHandle(forWritingTo: url) { defer { try? file.close() }; _ = try? file.seekToEnd(); try? file.write(contentsOf: data) }
        #endif
    }
}

private final class VideoMetalLayer: CAMetalLayer {
    // MoltenVK may request a 1x1 drawable during presentation. Preserve the
    // valid viewport, matching the existing Harbor iOS renderer workaround.
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set { if newValue.width > 1 && newValue.height > 1 { super.drawableSize = newValue } }
    }
}
