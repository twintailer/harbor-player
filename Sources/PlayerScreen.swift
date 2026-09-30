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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controls = true
    @State private var lastInteraction = Date()
    @State private var panel: Panel?
    @State private var detail: Detail?
    @State private var volumeLevel = Double(AVAudioSession.sharedInstance().outputVolume)
    @State private var style = SubtitleSettings.load()
    @State private var preset = "off"
    @State private var scrub = 0.0
    @State private var scrubbing = false
    @State private var originalBrightness: CGFloat?
    @State private var gestureStart: CGFloat?
    @State private var gestureSide = false
    @State private var hud: String?
    @State private var hudDeadline = Date.distantPast
    @State private var volume = MPVolumeView(frame: .zero)
    @State private var contentID = ""
    @State private var season = ""
    @State private var episode = ""
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
    enum Panel: String, Identifiable { case settings, speed, anime, audio, subtitles; var id: String { rawValue } }
    enum Detail: String, Identifiable { case subtitles, preferences, metadata; var id: String { rawValue } }

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
                            state.skip(Double(amount)); showHUD("\(amount > 0 ? "+" : "")\(amount) Sekunden"); touch()
                        case .second: withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { controls.toggle() }; touch()
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
                        else { setVolume(Double(level)) }
                        showHUD("\(gestureSide ? "Helligkeit" : "Lautstärke") \(Int(level * 100)) %")
                        touch()
                    }.onEnded { _ in gestureStart = nil; touch() })
                // Keep the system volume bridge attached, but clip its native
                // slider completely. iOS 26 gives even tiny sliders glass chrome.
                SystemVolumeView(volume: volume).frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
                if state.buffering && state.error == nil { ProgressView().tint(.white).scaleEffect(1.3).allowsHitTesting(false) }
                if controls || hud != nil || state.currentSegment != nil || closing {
                HarborGlassGroup {
                    ZStack {
                        if controls { overlay(wide: geometry.size.width > 600).transition(.opacity).allowsHitTesting(panel == nil).accessibilityHidden(panel != nil) }
                        if let hud, panel == nil {
                            Text(hud).font(.subheadline.monospacedDigit()).padding(.horizontal, 20).padding(.vertical, 12).harborGlass()
                                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 68).allowsHitTesting(false)
                        }
                        if let segment = state.currentSegment, panel == nil {
                            VStack { Spacer(); HStack { Spacer(); Button { state.seek(segment.end); touch() } label: { Label(segment.label, systemImage: "forward.end.fill").font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 13) }.buttonStyle(.plain).harborGlass(interactive: true) }.padding(.bottom, controls ? 152 : 28) }.padding(.horizontal, 24)
                        }
                        if closing { ProgressView("Schließen …").padding(20).harborGlass(radius: 20) }
                    }
                }.zIndex(1)
                }
                // Menus are a separate glass layer, so toolbar glass cannot merge
                // with them or draw its controls above the menu's text.
                if let selection = panel {
                    Color.black.opacity(0.18).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { closePanel() }
                        .accessibilityLabel("Einstellungen schließen").accessibilityAddTraits(.isButton).zIndex(2)
                    PlayerGlassPanel(title: panelTitle(selection), symbol: panelSymbol(selection), back: selection == .settings ? nil : { panel = .settings; touch() }, close: closePanel) {
                        panelContent(selection)
                    }
                    .id(selection)
                    .frame(width: min(360, geometry.size.width - 32), height: min(520, geometry.size.height - 24))
                    .padding(.trailing, 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).zIndex(3)
                }
            }.foregroundStyle(.white).tint(.white).buttonStyle(.plain)
        }
        .statusBarHidden().persistentSystemOverlays(.hidden)
        .sheet(item: $detail, onDismiss: { touch() }) { selection in
            NavigationStack { detailContent(selection).navigationTitle(detailTitle(selection)).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { detail = nil } } } }
                .presentationDetents([.large]).presentationCornerRadius(30).preferredColorScheme(.dark).tint(.white)
                .fileImporter(isPresented: $importFont, allowedContentTypes: [.font]) { result in importFontFile(result) }
                .fileImporter(isPresented: $importSubtitle, allowedContentTypes: [.data]) { result in importSubtitleFile(result) }
        }
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            UIApplication.shared.isIdleTimerDisabled = true
            contentID = request.contentID; season = request.season.map(String.init) ?? ""; episode = request.episode.map(String.init) ?? ""; anime = request.isAnime
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
            volumeLevel = Double(AVAudioSession.sharedInstance().outputVolume)
            if Date() >= hudDeadline { hud = nil }
            if Date().timeIntervalSince(lastInteraction) > controlsHideSeconds {
                hud = nil
                if !state.paused && !state.buffering && state.duration > 0 && panel == nil && detail == nil && !scrubbing { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { controls = false } }
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
            LinearGradient(stops: [.init(color: .black.opacity(0.28), location: 0), .init(color: .clear, location: 0.3), .init(color: .clear, location: 0.45), .init(color: .black.opacity(0.7), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            Button { state.toggle(); touch() } label: {
                Image(systemName: state.paused ? "play.fill" : "pause.fill").font(.system(size: 54, weight: .regular))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 2).frame(width: 90, height: 90).contentShape(Circle())
            }.accessibilityLabel(state.paused ? "Wiedergabe" : "Pause").accessibilityIdentifier("centerPlayPause").offset(y: -12)
            VStack {
                HStack(spacing: 10) {
                    icon("xmark", "Player schließen") { closePlayer() }.harborGlass(interactive: true)
                    icon("info", "Medien und Intro-Erkennung") { openDetail(.metadata) }.harborGlass(interactive: true)
                    Spacer()
                    volumeControl
                }
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 3) {
                            if let season = request.season, let episode = request.episode { Text("STAFFEL \(season)  ·  EPISODE \(episode)").font(.caption.weight(.medium)).tracking(1.2).foregroundStyle(.white.opacity(0.65)) }
                            Text(request.title.isEmpty ? "Harbor Player" : request.title).font(.system(size: wide ? 21 : 18, weight: .semibold)).lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        if state.animeActive { Label("Anime4K", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8)) }
                    }.padding(.bottom, 1)
                    PlaybackTimeline(position: state.position, duration: state.duration, step: Double(seekSeconds), scrubbing: $scrubbing, preview: $scrub, seek: state.seek, touch: touch)
                    HStack {
                        Text(timestamp(scrubbing ? scrub : state.position)).accessibilityIdentifier("playbackClock")
                        Spacer()
                        Text("−" + timestamp(max(0, state.duration - (scrubbing ? scrub : state.position)))).accessibilityLabel("Verbleibende Zeit")
                    }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6)).padding(.top, -3).padding(.bottom, 10)
                    if wide { HStack { transport; Spacer(minLength: 16); options } }
                    else { VStack(spacing: 8) { transport; options }.frame(maxWidth: .infinity) }
                }
            }.padding(.horizontal, 22).padding(.vertical, 12)
        }
    }
    private var volumeControl: some View {
        HStack(spacing: 10) {
            Text("\(Int(volumeLevel * 100)) %").font(.subheadline.monospacedDigit()).frame(width: 46)
            Slider(value: Binding(get: { volumeLevel }, set: { setVolume($0); touch() }), in: 0...1).frame(width: 100).accessibilityLabel("Lautstärke")
            Image(systemName: volumeLevel == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 18)).frame(width: 25)
        }.padding(.horizontal, 14).frame(height: 44).harborGlass().accessibilityElement(children: .contain)
    }
    private var transport: some View {
        HStack(spacing: 4) {
            icon("gobackward.\(seekSeconds)", "\(seekSeconds) Sekunden zurück") { state.skip(-Double(seekSeconds)) }
            icon(state.paused ? "play.fill" : "pause.fill", "Play/Pause") { state.toggle() }
            icon("goforward.\(seekSeconds)", "\(seekSeconds) Sekunden vor") { state.skip(Double(seekSeconds)) }
        }.padding(.horizontal, 8).padding(.vertical, 2).harborGlass()
    }
    private var options: some View {
        HStack(spacing: 4) {
            Button { openPanel(.speed) } label: { Text(String(format: "%g×", state.speed)).font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Playback speed")
            icon("sparkles.tv", "Anime4K") { openPanel(.anime) }
            icon("waveform", "Audio language") { openPanel(.audio) }
            icon("captions.bubble", "Subtitle language und Stil") { openPanel(.subtitles) }
            Rectangle().fill(.white.opacity(0.18)).frame(width: 0.5, height: 20).padding(.horizontal, 3)
            icon("gearshape", "Einstellungen") { openPanel(.settings) }
        }.padding(.horizontal, 8).padding(.vertical, 2).harborGlass()
    }
    private func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button { action(); touch() } label: { Image(systemName: symbol).font(.system(size: 21, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel(label)
    }
    @ViewBuilder private func panelContent(_ selection: Panel) -> some View {
        switch selection {
        case .settings:
            PlayerMenuRow(title: "Wiedergabetempo", subtitle: String(format: "%g×", state.speed), symbol: "speedometer", disclosure: true) { openPanel(.speed) }
            PlayerMenuRow(title: "Anime4K", subtitle: animeLabel(preset), symbol: "sparkles.tv", disclosure: true) { openPanel(.anime) }
            PlayerMenuRow(title: "Audiosprache", subtitle: selectedTrackLabel("audio"), symbol: "waveform", disclosure: true) { openPanel(.audio) }
            PlayerMenuRow(title: "Untertitel", subtitle: selectedTrackLabel("sub"), symbol: "captions.bubble", disclosure: true) { openPanel(.subtitles) }
            menuDivider
            PlayerMenuRow(title: "Sprachen & Bedienung", subtitle: "Bevorzugte Sprachen · Doppeltippen", symbol: "slider.horizontal.3", disclosure: true) { openDetail(.preferences) }.accessibilityIdentifier("openLanguagePreferences")
            PlayerMenuRow(title: "Medien & Skip Intro", symbol: "forward.end", disclosure: true) { openDetail(.metadata) }
        case .speed:
            ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], id: \.self) { value in
                PlayerMenuRow(title: String(format: "%g×", value), subtitle: value == 1 ? "Normal" : nil, selected: state.speed == value) { state.rate(value); closePanel() }
            }
        case .anime:
            ForEach(["off", "fast", "A", "B", "C", "hq"], id: \.self) { value in
                PlayerMenuRow(title: animeLabel(value), selected: preset == value) { preset = value; state.controller?.anime(value); touch() }
            }
            menuNote("Für den Einstieg: Schnell oder Modus A. Höhere Qualität benötigt mehr Leistung und Akku.")
        case .audio:
            trackRows("audio")
            menuDivider
            PlayerMenuRow(title: "Spuren wieder automatisch auswählen", symbol: "arrow.triangle.2.circlepath") { state.controller?.applyLanguagePreferences(); touch() }
            PlayerMenuRow(title: "Bevorzugte Sprachen", subtitle: "Audio · Untertitel · Forced", symbol: "globe", disclosure: true) { openDetail(.preferences) }
        case .subtitles:
            trackRows("sub")
            PlayerMenuRow(title: "Untertitel ausschalten", selected: !state.tracks.contains { $0.type == "sub" && $0.selected }) { state.controller?.selectTrack("sub", id: -1); touch() }
            menuDivider
            PlayerMenuRow(title: "Spuren wieder automatisch auswählen", symbol: "arrow.triangle.2.circlepath") { state.controller?.applyLanguagePreferences(); touch() }
            PlayerMenuRow(title: "Untertitel gestalten", subtitle: "Schrift · Farbe · Größe · Versatz · Import", symbol: "textformat", disclosure: true) { openDetail(.subtitles) }.accessibilityIdentifier("openSubtitleStyle")
            PlayerMenuRow(title: "Bevorzugte Sprachen", subtitle: "Forced- und Full-Automatik", symbol: "globe", disclosure: true) { openDetail(.preferences) }
        }
    }
    @ViewBuilder private func detailContent(_ selection: Detail) -> some View {
        switch selection {
        case .preferences:
            Form {
                LanguagePreferencesView()
                Section("Bedienleiste") { Stepper("Ausblenden nach \(Int(controlsHideSeconds)) Sekunden", value: $controlsHideSeconds, in: 3...30, step: 1) }
            }
        case .subtitles:
            Form {
                SubtitleEditor(style: $style, importFont: $importFont)
                Section("Externe Untertitel") {
                    TextField("https:// … .srt / .ass / .vtt", text: $externalSubtitle).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("URL laden") {
                        if let url = URL(string: externalSubtitle), ["http", "https"].contains(url.scheme ?? "") { state.controller?.addSubtitle(url.absoluteString) }
                    }
                    Button("Datei importieren") { importSubtitle = true }
                }
            }
        case .metadata:
            Form {
                Section("Intro-Erkennung") {
                    Text("Stremio-Metadaten und Dateinamen werden automatisch erkannt.").font(.footnote).foregroundStyle(.secondary)
                    TextField("Medien-ID (automatisch erkannt)", text: $contentID).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("detectedContentID")
                    TextField("Staffel", text: $season).keyboardType(.numberPad)
                    TextField("Episode", text: $episode).keyboardType(.numberPad)
                    Text("Anime-Zuordnung über AniZip/AniSkip erfolgt automatisch.").font(.footnote).foregroundStyle(.secondary)
                    Button("Zeiten suchen") { lookupRevision += 1 }
                    Text(state.skipStatus).font(.footnote).foregroundStyle(.secondary)
                    Text("Die Felder dienen nur als optionale Korrektur. Ohne verfügbare Zeitmarken erscheint kein Skip-Button.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Automatisch überspringen") {
                    Toggle("Intro", isOn: $autoSkipIntro); Toggle("Rückblick", isOn: $autoSkipRecap); Toggle("Abspann", isOn: $autoSkipOutro)
                }
                Section("Verbindung") {
                    Text(request.successCallback == nil ? "Kein Stremio-Rückkanal vorhanden. Für Fortsetzen und Rückgabe in Stremio „Infuse“ auswählen." : "Stremio-Fortsetzen aktiv. Start: \(timestamp(request.start)). Beim Schließen wird die aktuelle Position zurückgegeben.").font(.footnote)
                    Button("Mit \(request.url.scheme == "https" ? "HTTP" : "HTTPS") erneut öffnen") {
                        var parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
                        parts?.scheme = request.url.scheme == "https" ? "http" : "https"
                        if let url = parts?.url { detail = nil; restart(url) }
                    }
                }
            }
        }
    }
    @ViewBuilder private func trackRows(_ type: String) -> some View {
        let tracks = state.tracks.filter { $0.type == type }
        if tracks.isEmpty { menuNote("Keine Spuren verfügbar") }
        ForEach(tracks) { track in
            PlayerMenuRow(title: trackLabel(track), subtitle: [track.title, track.codec.uppercased(), TrackPreferences.isForced(track) ? "Forced" : (type == "sub" ? "Vollständig" : "")].filter { !$0.isEmpty }.joined(separator: " · "), selected: track.selected) {
                state.controller?.selectTrack(type, id: track.id); touch()
            }.accessibilityIdentifier("track-\(type)-\(track.id)").accessibilityValue(track.selected ? "selected" : "unselected")
        }
    }
    private var menuDivider: some View { Divider().overlay(.white.opacity(0.08)).padding(.horizontal, 10).padding(.vertical, 8) }
    private func menuNote(_ text: String) -> some View { Text(text).font(.footnote).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
    private func trackLabel(_ track: MPVTrack) -> String { track.lang.isEmpty ? "Spur \(track.id)" : Locale.current.localizedString(forLanguageCode: TrackPreferences.normalized(track.lang)) ?? track.lang }
    private func selectedTrackLabel(_ type: String) -> String {
        guard let track = state.tracks.first(where: { $0.type == type && $0.selected }) else { return type == "sub" ? "Aus" : "Automatisch" }
        return trackLabel(track) + (TrackPreferences.isForced(track) ? " · Forced" : "")
    }
    private func openPanel(_ value: Panel) { controls = true; panel = value; touch() }
    private func closePanel() { panel = nil; touch() }
    private func openDetail(_ value: Detail) { panel = nil; detail = value; touch() }
    private func setVolume(_ value: Double) {
        volumeLevel = value
        if let slider = volume.subviews.compactMap({ $0 as? UISlider }).first { slider.value = Float(value); slider.sendActions(for: .valueChanged) }
    }
    private var lookupKey: String { "\(request.id):\(Int(state.duration)):\(state.chapters.hashValue):\(lookupRevision)" }
    private func lookup() async {
        guard state.duration > 0 else { return }
        state.segments = IntroSkipService.merge([IntroSkipService.chapterSegments(state.chapters, duration: state.duration)], duration: state.duration)
        var identity = request
        identity.contentID = contentID; identity.season = Int(season); identity.episode = Int(episode)
        identity = await IntroSkipService.identify(identity)
        guard !Task.isCancelled else { return }
        contentID = identity.contentID; season = identity.season.map(String.init) ?? ""; episode = identity.episode.map(String.init) ?? ""
        state.skipStatus = "Suche in AniSkip, TheIntroDB und Kapiteln …"
        let values = await IntroSkipService.segments(contentID: contentID, season: Int(season), episode: Int(episode), duration: state.duration, isAnime: anime, chapters: state.chapters) { partial in
            if !Task.isCancelled { state.segments = partial }
        }
        guard !Task.isCancelled else { return }
        state.segments = values
        state.skipStatus = values.isEmpty ? (contentID.isEmpty ? "Stremio hat keine Medien-ID übergeben und der Dateiname ist nicht eindeutig. Kapitel werden weiterhin geprüft." : "Für diese Folge sind aktuell keine passenden Zeitmarken verfügbar oder der Dienst ist nicht erreichbar.") : "\(values.count) Abschnitte gefunden. Der Skip-Button erscheint im passenden Abschnitt."
    }
    private func shouldAutoSkip(_ segment: SkipSegment) -> Bool { switch segment.kind { case .intro: return autoSkipIntro; case .recap: return autoSkipRecap; case .outro: return autoSkipOutro } }
    private func touch() { lastInteraction = Date() }
    private func showHUD(_ text: String) { hud = text; hudDeadline = Date().addingTimeInterval(1.2) }
    private func timestamp(_ seconds: Double) -> String { let n = Int(max(0, seconds)); return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%d:%02d", n / 60, n % 60) }
    private func panelTitle(_ panel: Panel) -> String { switch panel { case .settings: return "Einstellungen"; case .speed: return "Wiedergabetempo"; case .anime: return "Anime4K"; case .audio: return "Audiosprache"; case .subtitles: return "Untertitel" } }
    private func panelSymbol(_ panel: Panel) -> String { switch panel { case .settings: return "gearshape"; case .speed: return "speedometer"; case .anime: return "sparkles.tv"; case .audio: return "waveform"; case .subtitles: return "captions.bubble" } }
    private func detailTitle(_ detail: Detail) -> String { switch detail { case .preferences: return "Sprachen & Bedienung"; case .subtitles: return "Untertitel gestalten"; case .metadata: return "Medien & Skip Intro" } }
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
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        volume.showsRouteButton = false
        volume.frame = CGRect(x: -1000, y: -1000, width: 160, height: 44)
        container.addSubview(volume)
        return container
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
