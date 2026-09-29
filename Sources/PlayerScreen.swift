import SwiftUI
import MediaPlayer
import UniformTypeIdentifiers
import CoreText

struct PlayerScreen: View {
    @State var request: PlaybackRequest
    @StateObject private var state = PlayerState()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var playbackReturn: PlaybackReturn
    @State private var controls = true
    @State private var lastInteraction = Date()
    @State private var panel: Panel?
    @State private var style = SubtitleSettings.load()
    @State private var preset = "off"
    @State private var scrub = 0.0
    @State private var scrubbing = false
    @State private var originalBrightness: CGFloat?
    @State private var gestureStart: CGFloat?
    @State private var gestureSide = false
    @State private var hud: String?
    @State private var volume = MPVolumeView(frame: .zero)
    @State private var contentID = ""
    @State private var season = "1"
    @State private var episode = "1"
    @State private var anime = false
    @State private var lookupRevision = 0
    @State private var autoSkipped: Set<String> = []
    @State private var externalSubtitle = ""
    @State private var importFont = false
    @State private var importSubtitle = false
    @State private var closing = false
    @State private var pendingExternalClose = false
    @AppStorage("autoSkipIntro") private var autoSkipIntro = false
    @AppStorage("autoSkipRecap") private var autoSkipRecap = false
    @AppStorage("autoSkipOutro") private var autoSkipOutro = false
    @AppStorage("controlsHideSeconds") private var controlsHideSeconds = 4.0
    @AppStorage("preferredAudio") private var preferredAudio = TrackPreferences.systemLanguage
    @AppStorage("preferredSubtitles") private var preferredSubtitles = TrackPreferences.systemLanguage
    @AppStorage("preferForced") private var preferForced = true
    @AppStorage("seekSeconds") private var seekSeconds = 15
    private let pulse = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    enum Panel: String, Identifiable { case speed, anime, audio, subtitles, metadata; var id: String { rawValue } }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VideoSurface(request: request, state: state).id(request.id).ignoresSafeArea()
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture(count: 1)).onEnded { value in
                        switch value {
                        case .first(let tap):
                            let amount = tap.location.x < geometry.size.width / 2 ? -seekSeconds : seekSeconds
                            state.skip(Double(amount)); hud = "\(amount > 0 ? "+" : "")\(amount) Sekunden"; touch()
                        case .second: controls.toggle(); touch()
                        }
                    })
                    .simultaneousGesture(DragGesture(minimumDistance: 18).onChanged { value in
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        if gestureStart == nil {
                            gestureSide = value.startLocation.x < geometry.size.width / 2
                            gestureStart = gestureSide ? UIScreen.main.brightness : CGFloat(AVAudioSession.sharedInstance().outputVolume)
                        }
                        let level = min(1, max(0, (gestureStart ?? 0) - value.translation.height / (geometry.size.height * 0.75)))
                        if gestureSide { UIScreen.main.brightness = level }
                        else if let slider = volume.subviews.compactMap({ $0 as? UISlider }).first {
                            slider.value = Float(level); slider.sendActions(for: .valueChanged)
                        }
                        hud = "\(gestureSide ? "Helligkeit" : "Lautstärke") \(Int(level * 100)) %"
                        touch()
                    }.onEnded { _ in gestureStart = nil; touch() })
                SystemVolumeView(volume: volume).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false)
                if state.buffering && state.error == nil { ProgressView().tint(.mint).scaleEffect(1.5).allowsHitTesting(false) }
                if closing { ProgressView("Schließen …").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) }
                if controls { overlay(wide: geometry.size.width > 600) }
                if let hud { Text(hud).font(.headline.monospacedDigit()).padding().background(.ultraThinMaterial, in: Capsule()).frame(maxHeight: .infinity, alignment: .top).padding(.top, 70).allowsHitTesting(false) }
                if let segment = state.currentSegment {
                    VStack { Spacer(); HStack { Spacer(); Button { state.seek(segment.end); touch() } label: { Label(segment.label, systemImage: "forward.end.fill").padding(8) }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black) }.padding(.bottom, controls ? 150 : 35) }.padding(.horizontal, 26)
                }
            }.foregroundStyle(.white)
        }
        .statusBarHidden().persistentSystemOverlays(.hidden)
        .sheet(item: $panel, onDismiss: { touch() }) { selection in
            NavigationStack { panelContent(selection).navigationTitle(panelTitle(selection)).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { panel = nil } } } }
                .presentationDetents([.medium, .large]).preferredColorScheme(.dark).tint(.mint)
                .fileImporter(isPresented: $importFont, allowedContentTypes: [.font]) { result in importFontFile(result) }
                .fileImporter(isPresented: $importSubtitle, allowedContentTypes: [.data]) { result in importSubtitleFile(result) }
        }
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            UIApplication.shared.isIdleTimerDisabled = true
            contentID = request.contentID; season = String(request.season ?? 1); episode = String(request.episode ?? 1); anime = request.isAnime
        }
        .onDisappear { state.controller?.shutdown(); UIApplication.shared.isIdleTimerDisabled = false; if let originalBrightness { UIScreen.main.brightness = originalBrightness } }
        .onChange(of: scenePhase) { _, value in if value != .active { state.controller?.property("pause", "yes") } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in state.controller?.property("pause", "yes") }
        .onReceive(NotificationCenter.default.publisher(for: .harborReplacePlayback)) { _ in pendingExternalClose = true; closePlayer() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { state.controller?.property("pause", "yes") }
        }
        .onChange(of: style) { _, value in state.controller?.style(value) }
        .onChange(of: preferredAudio) { _, _ in state.controller?.applyLanguagePreferences() }
        .onChange(of: preferredSubtitles) { _, _ in state.controller?.applyLanguagePreferences() }
        .onChange(of: preferForced) { _, _ in state.controller?.applyLanguagePreferences() }
        .onReceive(pulse) { _ in
            if Date().timeIntervalSince(lastInteraction) > controlsHideSeconds {
                hud = nil
                if !state.paused && !state.buffering && state.duration > 0 && panel == nil && !scrubbing { controls = false }
            }
            if let segment = state.currentSegment, !autoSkipped.contains(segment.id), shouldAutoSkip(segment) { autoSkipped.insert(segment.id); state.seek(segment.end) }
        }
        .task(id: lookupKey) { await lookup() }
        .alert("Wiedergabe", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("Erneut versuchen") { state.error = nil; restart(request.url) }
            Button("Schließen", role: .cancel) { state.error = nil }
        } message: { Text(state.error ?? "") }
    }

    private func overlay(wide: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            Button { state.toggle(); touch() } label: { Image(systemName: state.paused ? "play.fill" : "pause.fill").font(.system(size: 38, weight: .semibold)).frame(width: 84, height: 84).background(.ultraThinMaterial, in: Circle()) }.accessibilityLabel(state.paused ? "Wiedergabe" : "Pause").accessibilityIdentifier("centerPlayPause")
            VStack {
                HStack {
                    icon("chevron.down", "Player schließen") { closePlayer() }
                    Text(request.title.isEmpty ? "Harbor Player" : request.title).font(.headline).lineLimit(1)
                    Spacer()
                    if state.animeActive { Text("Anime4K").font(.caption.bold()).foregroundStyle(.mint) }
                    icon("info.circle", "Medien und Intro-Erkennung") { panel = .metadata }
                }
                Spacer()
                VStack(spacing: 6) {
                    Slider(value: Binding(get: { scrubbing ? scrub : min(state.position, max(1, state.duration)) }, set: { scrub = $0 }), in: 0...max(1, state.duration), onEditingChanged: { editing in scrubbing = editing; if !editing { state.seek(scrub) }; touch() }).tint(.mint).disabled(state.duration <= 0).accessibilityLabel("Wiedergabeposition")
                    HStack { Text(timestamp(scrubbing ? scrub : state.position)).accessibilityIdentifier("playbackClock"); Spacer(); Text(timestamp(state.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if wide { HStack { transport; Spacer(); options } }
                    else { VStack(spacing: 2) { HStack { transport; Spacer() }; HStack { Spacer(); options } } }
                }
            }.padding(.horizontal, 22).padding(.vertical, 12)
        }
    }
    private var transport: some View {
        HStack(spacing: 10) {
            icon("gobackward.\(seekSeconds)", "\(seekSeconds) Sekunden zurück") { state.skip(-Double(seekSeconds)) }
            icon(state.paused ? "play.fill" : "pause.fill", "Play/Pause") { state.toggle() }
            icon("goforward.\(seekSeconds)", "\(seekSeconds) Sekunden vor") { state.skip(Double(seekSeconds)) }
        }
    }
    private var options: some View {
        HStack(spacing: 8) {
            Button { panel = .speed; touch() } label: { Text(String(format: "%g×", state.speed)).font(.headline).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Playback speed")
            icon("sparkles.tv", "Anime4K") { panel = .anime }
            icon("waveform", "Audio language") { panel = .audio }
            icon("captions.bubble", "Subtitle language und Stil") { panel = .subtitles }
        }
    }
    private func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button { action(); touch() } label: { Image(systemName: symbol).font(.system(size: 22, weight: .medium)).frame(width: 44, height: 44) }.accessibilityLabel(label)
    }
    @ViewBuilder private func panelContent(_ selection: Panel) -> some View {
        switch selection {
        case .speed:
            List([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], id: \.self) { value in Button { state.rate(value); panel = nil } label: { HStack { Text(String(format: "%g×", value)); Spacer(); if state.speed == value { Image(systemName: "checkmark") } } } }
        case .anime:
            List {
                ForEach(["off", "fast", "A", "B", "C", "hq"], id: \.self) { value in Button { preset = value; state.controller?.anime(value) } label: { HStack { Text(animeLabel(value)); Spacer(); if preset == value { Image(systemName: "checkmark") } } } }
                Text("Echte Anime4K-Shader direkt in der GPU-Pipeline. Hohe Qualität benötigt mehr Leistung und Akku. Für den Einstieg: Schnell oder Modus A.").font(.footnote).foregroundStyle(.secondary)
            }
        case .audio: Form { Section("Audiospur") { trackRows("audio"); Button("Spuren wieder automatisch auswählen") { state.controller?.applyLanguagePreferences() } }; LanguagePreferencesView() }
        case .subtitles:
            Form {
                Section("Sprache") {
                    Button("Untertitel ausschalten") { state.controller?.selectTrack("sub", id: -1) }
                    Button("Spuren wieder automatisch auswählen") { state.controller?.applyLanguagePreferences() }
                    trackRows("sub")
                }
                Section("Externe Untertitel") {
                    TextField("https:// … .srt / .ass / .vtt", text: $externalSubtitle).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("URL laden") {
                        if let url = URL(string: externalSubtitle), ["http", "https"].contains(url.scheme ?? "") { state.controller?.addSubtitle(url.absoluteString) }
                    }
                    Button("Datei importieren") { importSubtitle = true }
                }
                SubtitleEditor(style: $style, importFont: $importFont)
                LanguagePreferencesView()
            }
        case .metadata:
            Form {
                Section("Intro-Erkennung") {
                    TextField("IMDb tt… / mal:… / kitsu:…", text: $contentID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Staffel", text: $season).keyboardType(.numberPad)
                    TextField("Episode", text: $episode).keyboardType(.numberPad)
                    Toggle("Anime", isOn: $anime)
                    Button("Zeiten suchen") { lookupRevision += 1 }
                    Text(state.skipStatus).font(.footnote).foregroundStyle(.secondary)
                    Text("MyAnimeList-IDs gelten pro Anime-Staffel. Die Episodennummer muss zur gewählten ID passen.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Automatisch überspringen") {
                    Toggle("Intro", isOn: $autoSkipIntro); Toggle("Rückblick", isOn: $autoSkipRecap); Toggle("Abspann", isOn: $autoSkipOutro)
                }
                Section("Verbindung") {
                    Text(request.successCallback == nil ? "Kein Stremio-Rückkanal vorhanden. Für Fortsetzen und Rückgabe in Stremio „Infuse“ auswählen." : "Stremio-Fortsetzen aktiv. Start: \(timestamp(request.start)). Beim Schließen wird die aktuelle Position zurückgegeben.").font(.footnote)
                    Stepper("Bedienleiste: \(Int(controlsHideSeconds)) Sekunden", value: $controlsHideSeconds, in: 3...30, step: 1)
                    Button("Mit \(request.url.scheme == "https" ? "HTTP" : "HTTPS") erneut öffnen") {
                        var parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
                        parts?.scheme = request.url.scheme == "https" ? "http" : "https"
                        if let url = parts?.url { panel = nil; restart(url) }
                    }
                }
            }
        }
    }
    @ViewBuilder private func trackRows(_ type: String) -> some View {
        let tracks = state.tracks.filter { $0.type == type }
        if tracks.isEmpty { Text("Keine Spuren verfügbar").foregroundStyle(.secondary) }
        ForEach(tracks) { track in
            Button { state.controller?.selectTrack(type, id: track.id) } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(track.lang.isEmpty ? "Spur \(track.id)" : Locale.current.localizedString(forLanguageCode: track.lang) ?? track.lang)
                        Text([track.title, track.codec, track.forced ? "Forced" : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }; Spacer(); if track.selected { Image(systemName: "checkmark") }
                }
            }.accessibilityIdentifier("track-\(type)-\(track.id)").accessibilityValue(track.selected ? "selected" : "unselected")
        }
    }
    private var lookupKey: String { "\(request.id):\(Int(state.duration)):\(state.chapters.hashValue):\(lookupRevision)" }
    private func lookup() async {
        guard state.duration > 0 else { return }
        state.segments = IntroSkipService.merge([IntroSkipService.chapterSegments(state.chapters, duration: state.duration)], duration: state.duration)
        state.skipStatus = "Suche in AniSkip, TheIntroDB und Kapiteln …"
        let values = await IntroSkipService.segments(contentID: contentID, season: Int(season), episode: Int(episode), duration: state.duration, isAnime: anime, chapters: state.chapters)
        guard !Task.isCancelled else { return }
        state.segments = values
        state.skipStatus = values.isEmpty ? "Keine Zeiten gefunden. Medien-ID und Episode prüfen; nicht jede Folge ist erfasst." : "\(values.count) Abschnitte gefunden. Der Skip-Button erscheint im passenden Abschnitt."
    }
    private func shouldAutoSkip(_ segment: SkipSegment) -> Bool { switch segment.kind { case .intro: return autoSkipIntro; case .recap: return autoSkipRecap; case .outro: return autoSkipOutro } }
    private func touch() { lastInteraction = Date() }
    private func timestamp(_ seconds: Double) -> String { let n = Int(max(0, seconds)); return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%d:%02d", n / 60, n % 60) }
    private func panelTitle(_ panel: Panel) -> String { switch panel { case .speed: return "Playback speed"; case .anime: return "Anime4K"; case .audio: return "Audio language"; case .subtitles: return "Untertitel"; case .metadata: return "Medien & Skip Intro" } }
    private func animeLabel(_ value: String) -> String { switch value { case "off": return "Aus"; case "fast": return "Schnell · DTD"; case "hq": return "Hohe Qualität · Modus A"; default: return "Modus \(value) · Balanced" } }
    private func restart(_ url: URL) {
        guard !closing else { return }; closing = true
        let replacement = PlaybackRequest(url: url, title: request.title, contentID: contentID, season: Int(season), episode: Int(episode), isAnime: anime, start: state.position, subtitle: request.subtitle, successCallback: request.successCallback)
        let replace = {
            if pendingExternalClose { dismiss(); return }
            request = replacement
            state.buffering = true; state.segments = []; state.animeActive = false; preset = "off"; state.speed = 1; autoSkipped = []; closing = false
        }
        if let controller = state.controller { controller.shutdown(completion: replace) } else { replace() }
    }
    private func closePlayer() {
        guard !closing else { return }; closing = true
        if let controller = state.controller {
            controller.finishPlayback { position, loaded in
                if !pendingExternalClose { playbackReturn.prepare(request, position: position, loaded: loaded) }
                dismiss()
            }
        } else { dismiss() }
    }
    private func importFontFile(_ result: Result<URL, Error>) {
        do {
            let source = try result.get(); let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: source)
            guard data.count < 30_000_000, let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider), let name = font.postScriptName else { throw PlaybackRequest.RequestError.invalidURL }
            let folder = FontStore.directory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            try data.write(to: destination, options: .atomic)
            CTFontManagerRegisterFontsForURL(destination as CFURL, .process, nil)
            state.controller?.property("sub-fonts-dir", folder.path)
            style.font = name as String
        } catch { state.error = "Schrift konnte nicht importiert werden: \(error.localizedDescription)" }
    }
    private func importSubtitleFile(_ result: Result<URL, Error>) {
        do {
            let source = try result.get(); let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
            guard ["srt", "ass", "ssa", "vtt", "sub"].contains(source.pathExtension.lowercased()) else { throw PlaybackRequest.RequestError.invalidURL }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
            try FileManager.default.copyItem(at: source, to: target)
            state.controller?.addSubtitle(target.path)
        } catch { state.error = "Untertitel konnten nicht importiert werden: \(error.localizedDescription)" }
    }
}

private struct SystemVolumeView: UIViewRepresentable {
    let volume: MPVolumeView
    func makeUIView(context: Context) -> MPVolumeView { volume.showsRouteButton = false; return volume }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
