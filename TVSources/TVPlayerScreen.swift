import SwiftUI
import AVFoundation

struct TVPlayerScreen: View {
    @State var request: PlaybackRequest
    @StateObject private var state = PlayerState()
    @EnvironmentObject private var playbackReturn: PlaybackReturn
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controls = true
    @State private var interaction = Date()
    @State private var panel: Panel?
    @State private var detail: Detail?
    @State private var closing = false
    @State private var replacing = false
    @AppStorage("tvAnimeSelection") private var preset = "auto"
    @AppStorage("tvAnimeSavedMode") private var savedAnimeMode = "A"
    @AppStorage("tvAnimeTier") private var animeTier = "balanced"
    @AppStorage("tvAnimeProtection") private var animeProtection = true
    @State private var scrubPosition: Double?
    @State private var lastScrubMove = Date.distantPast
    @State private var scrubDirection = 0
    @State private var scrubRepeats = 0
    @State private var style = SubtitleSettings.load()
    @State private var skipped: Set<String> = []
    @State private var identity: PlaybackRequest?
    @State private var episodeTitle: String?
    @State private var contentID = ""
    @State private var season = ""
    @State private var episode = ""
    @State private var lookupRevision = 0
    @FocusState private var focus: Control?
    @AppStorage("seekSeconds") private var seekSeconds = 15
    @AppStorage("controlsHideSeconds") private var hideSeconds = 6.0
    @AppStorage("autoSkipIntro") private var autoIntro = false
    @AppStorage("autoSkipRecap") private var autoRecap = false
    @AppStorage("autoSkipOutro") private var autoOutro = false
    @AppStorage("preferredAudio") private var audio = TrackPreferences.systemLanguage
    @AppStorage("preferredSubtitles") private var subtitles = TrackPreferences.systemLanguage
    @AppStorage("preferForced") private var forced = true
    private let pulse = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    enum Control: Hashable { case screen, close, info, back, play, forward, timeline, speed, anime, audio, subtitles, settings, skip }
    enum Panel: String, Identifiable { case speed, anime, audio, subtitles; var id: String { rawValue } }
    enum Detail: String, Identifiable { case preferences, subtitles, metadata; var id: String { rawValue } }
    private var playerCanvas: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(request: request, state: state).id(request.id).ignoresSafeArea().allowsHitTesting(false)
            if !controls && panel == nil {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    .focusable().focusEffectDisabled().focused($focus, equals: .screen)
                    .onTapGesture { reveal() }
                    .accessibilityLabel("Bedienleiste öffnen").accessibilityAddTraits(.isButton)
                    .onMoveCommand { direction in
                        if direction == .left { state.skip(-Double(seekSeconds)) }
                        else if direction == .right { state.skip(Double(seekSeconds)) }
                        else { reveal() }
                        touch()
                    }
            }
            if controls { overlay }
            if state.buffering && state.error == nil { ProgressView().scaleEffect(1.5).allowsHitTesting(false) }
            if let segment = state.currentSegment, panel == nil, detail == nil {
                VStack { Spacer(); HStack { Spacer(); Button(segment.label) { state.seek(segment.end); touch() }
                    .focused($focus, equals: .skip).accessibilityIdentifier("skipSegment") }.padding(.bottom, controls ? 205 : 55) }.padding(.horizontal, 64)
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["HARBOR_TEST_CAPTURE_CALLBACK"] == "1" {
                Text(verbatim: "\(state.audioOutput)|\(Int(state.audioSampleRate))|\(Int(state.cacheAhead))|\(state.hardwareDecoder)")
                    .font(.system(size: 12, design: .monospaced)).padding(8).background(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false).accessibilityIdentifier("playbackDiagnostics")
                Text(verbatim: "\(state.shaderCount)|\(state.droppedFrames)|\(state.animeStatus)")
                    .font(.system(size: 12)).padding(8).background(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false).accessibilityIdentifier("animeDiagnostics")
                Text(verbatim: "\(state.subtitleOverride)|\(state.subtitleText)")
                    .font(.system(size: 12)).padding(8).background(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false).accessibilityIdentifier("subtitleDiagnostics")
            }
            #endif
            if closing { ProgressView("Schließen …").padding(30).tvGlass() }
        }
    }
    var body: some View {
        playerCanvas.preferredColorScheme(.dark).tint(.white)
            .onPlayPauseCommand { commitScrub(); state.toggle(); reveal() }
            .onExitCommand {
                if panel != nil { panel = nil; reveal() }
                else if controls { commitScrub(); controls = false; focus = .screen }
                else { close() }
            }
            .onChange(of: focus) { old, value in if old == .timeline && value != .timeline { commitScrub() }; touch() }
            .onChange(of: state.duration) { old, value in if old == 0 && value > 0 { applyAnime() } }
            .onChange(of: identity?.isAnime) { _, _ in if preset == "auto" { applyAnime() } }
            .onChange(of: animeTier) { _, _ in applyAnime() }
            .onChange(of: animeProtection) { _, _ in applyAnime() }
            .onChange(of: panel) { _, value in if value != nil { focus = nil } }
            .onChange(of: detail) { _, value in if value != nil { focus = nil } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { state.controller?.property("pause", "yes") } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in state.controller?.property("pause", "yes") }
            .onReceive(NotificationCenter.default.publisher(for: .harborReplacePlayback)) { _ in replacing = true; close() }
            .onChange(of: style) { _, value in state.controller?.style(value) }
            .onChange(of: audio) { _, _ in state.controller?.applyLanguagePreferences() }
            .onChange(of: subtitles) { _, _ in state.controller?.applyLanguagePreferences() }
            .onChange(of: forced) { _, _ in state.controller?.applyLanguagePreferences() }
            .onAppear {
                contentID = request.contentID; season = request.season.map(String.init) ?? ""; episode = request.episode.map(String.init) ?? ""
                focus = .play; UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear { state.controller?.shutdown(); UIApplication.shared.isIdleTimerDisabled = false }
            .onReceive(pulse) { _ in updatePlaybackControls() }
            .task(id: "\(request.id):\(Int(state.duration)):\(state.chapters.hashValue):\(lookupRevision)") { await lookup() }
            .task(id: "\((identity ?? request).contentID):\((identity ?? request).season ?? 0):\((identity ?? request).episode ?? 0)") {
                let value = identity ?? request
                episodeTitle = nil
                let title = await PlaybackMetadataService.title(for: value, language: Locale.preferredLanguages.first ?? "en") { episodeTitle = $0 }
                if !Task.isCancelled { episodeTitle = title }
            }
            .sheet(item: $panel, onDismiss: restoreAfterMenu) { menu($0) }
            .sheet(item: $detail, onDismiss: restoreAfterMenu) { selection in
                switch selection {
                case .preferences: TVPreferences()
                case .subtitles: TVSubtitleSettings(style: $style, controller: state.controller)
                case .metadata: metadata
                }
            }
            .alert("Wiedergabe", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
                Button("Schließen") { state.error = nil; close() }
            } message: { Text(state.error ?? "") }
    }
    private var overlay: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.3), .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack {
                HStack(spacing: 12) {
                    icon("xmark", "Player schließen", .close) { close() }
                    icon("info", "Medien und Intro-Erkennung", .info) { detail = .metadata }
                    Spacer()
                }.focusSection()
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(episodeTitle ?? PlaybackMetadataService.fallback(identity ?? request)).font(.system(size: 30, weight: .semibold)).lineLimit(1).accessibilityIdentifier("episodeTitle")
                        Spacer()
                        if state.animeActive { Label("Anime4K", systemImage: "sparkles").font(.callout).accessibilityIdentifier("animeActive") }
                    }
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            icon("gobackward.\(seekSeconds)", "Zurückspringen", .back) { state.skip(-Double(seekSeconds)); touch() }
                            icon(state.paused ? "play.fill" : "pause.fill", "Play-Pause", .play) { commitScrub(); state.toggle(); touch() }
                                .accessibilityValue(state.paused ? "paused" : "playing")
                            icon("goforward.\(seekSeconds)", "Vorspringen", .forward) { state.skip(Double(seekSeconds)); touch() }
                        }.focusSection()
                        Spacer()
                        HStack(spacing: 10) {
                            Button(String(format: "%g×", state.speed)) { panel = .speed; touch() }.focused($focus, equals: .speed).accessibilityLabel("Playback speed")
                            icon("sparkles.tv", "Anime4K", .anime) { panel = .anime; touch() }
                            icon("waveform", "Audio language", .audio) { panel = .audio; touch() }
                            icon("captions.bubble", "Subtitle language", .subtitles) { panel = .subtitles; touch() }
                            icon("gearshape", "Einstellungen", .settings) { detail = .preferences; touch() }
                        }.focusSection()
                    }.buttonStyle(TVPlaybackButtonStyle())
                    Button { commitScrub(); touch() } label: {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.25))
                                Capsule().fill(.white).frame(width: geometry.size.width * min(1, max(0, state.duration > 0 ? (scrubPosition ?? state.position) / state.duration : 0)))
                                if focus == .timeline {
                                    Circle().fill(.white).frame(width: 18, height: 18)
                                        .offset(x: max(0, min(geometry.size.width - 18, geometry.size.width * (state.duration > 0 ? (scrubPosition ?? state.position) / state.duration : 0) - 9)))
                                }
                            }.frame(height: focus == .timeline ? 7 : 5).frame(maxHeight: .infinity)
                        }.frame(height: 30).contentShape(Rectangle())
                    }.buttonStyle(TVTimelineButtonStyle()).focused($focus, equals: .timeline).accessibilityLabel("Zeitleiste").accessibilityIdentifier("playbackTimeline")
                        .accessibilityValue(clock(scrubPosition ?? state.position))
                        .onMoveCommand { direction in
                            if direction == .left { scrub(-1) }
                            if direction == .right { scrub(1) }
                            touch()
                        }
                    HStack { Text(clock(scrubPosition ?? state.position)).accessibilityIdentifier("playbackClock"); Spacer(); Text(clock(state.duration)) }.font(.system(size: 22).monospacedDigit()).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 64).padding(.vertical, 42).buttonStyle(TVPlaybackButtonStyle())
        }.ignoresSafeArea()
    }
    private func icon(_ symbol: String, _ label: String, _ control: Control, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .focused($focus, equals: control).accessibilityLabel(label)
    }
    private func menu(_ selection: Panel) -> some View {
        TVSheet(title: panelTitle(selection)) {
            switch selection {
            case .speed:
                ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], id: \.self) { speed in
                    choice(String(format: "%g×", speed), selected: abs(state.speed - speed) < 0.01) { state.rate(speed); panel = nil }
                }
            case .anime:
                ForEach(["auto", "off", "fast"] + Anime4KPresets.modes, id: \.self) { value in
                    choice(Anime4KPresets.label(value), selected: preset == value) {
                        preset = value
                        if Anime4KPresets.modes.contains(value) { savedAnimeMode = value }
                        applyAnime()
                    }.accessibilityIdentifier("anime-" + value)
                }
                Picker("Qualität", selection: $animeTier) { Text("Balanced · S-CNN").tag("balanced"); Text("Max Qualität · VL/M-CNN").tag("hq") }
                Toggle("Leistungsschutz", isOn: $animeProtection)
                Text("Balanced verwendet dieselben kompakten Ketten wie Harbor tvOS. VL/M kostet mehr GPU-Leistung. Über 1080p bleibt Anime4K aus; bei anhaltenden Frame-Drops wechselt der Leistungsschutz zu DTD. Auto nutzt den gespeicherten Modus für erkannte Anime.").font(.callout).foregroundStyle(.secondary)
                Text(state.animeStatus).font(.callout)
            case .audio:
                tracks("audio")
                Button("Automatische Sprachauswahl") { state.controller?.applyLanguagePreferences() }
            case .subtitles:
                choice("Aus", selected: !state.tracks.contains { $0.type == "sub" && $0.selected }) { state.controller?.selectTrack("sub", id: -1) }
                tracks("sub")
                Button("Automatische Sprachauswahl") { state.controller?.applyLanguagePreferences() }
                Button("Untertitel gestalten") { panel = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { detail = .subtitles } }
                    .accessibilityIdentifier("openSubtitleStyle")
            }
        }
    }
    @ViewBuilder private func tracks(_ type: String) -> some View {
        if state.tracks.filter({ $0.type == type }).isEmpty { Text("Keine Spuren verfügbar").foregroundStyle(.secondary) }
        ForEach(state.tracks.filter { $0.type == type }) { track in
            choice([Locale.current.localizedString(forLanguageCode: TrackPreferences.normalized(track.lang)) ?? track.lang, track.title, track.codec.uppercased(), TrackPreferences.isForced(track) ? "Forced" : ""].filter { !$0.isEmpty }.joined(separator: " · "), selected: track.selected) {
                state.controller?.selectTrack(type, id: track.id)
            }.accessibilityIdentifier("track-\(type)-\(track.id)").accessibilityValue(track.selected ? "selected" : "unselected")
        }
    }
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark") } }.frame(maxWidth: .infinity, alignment: .leading) }
    }
    private var metadata: some View {
        TVSheet(title: "Medien & Skip Intro") {
            Text("Medien und Folgen werden automatisch erkannt. Diese Felder dienen nur als optionale Korrektur.").font(.callout).foregroundStyle(.secondary)
            TextField("Medien-ID", text: $contentID).accessibilityIdentifier("detectedContentID")
            TextField("Staffel", text: $season)
            TextField("Episode", text: $episode)
            Text(state.skipStatus).foregroundStyle(.secondary)
            Text("Audio: \(state.audioOutput.isEmpty ? "Keine Ausgabe" : state.audioOutput) · \(Int(state.audioSampleRate)) Hz")
            Text("Puffer: \(Int(state.cacheAhead)) Sekunden · Decoder: \(state.hardwareDecoder)")
            Text("\(state.animeStatus) · \(state.shaderCount) Shader · \(state.droppedFrames) verworfene Frames")
            Button("Zeiten erneut suchen") { lookupRevision += 1 }
            Toggle("Intro automatisch überspringen", isOn: $autoIntro)
            Toggle("Recap automatisch überspringen", isOn: $autoRecap)
            Toggle("Abspann automatisch überspringen", isOn: $autoOutro)
            Text(request.successCallback == nil ? "Stremio hat keinen Rückkanal übergeben." : "Die Position wird beim Schließen an Stremio übergeben.").foregroundStyle(.secondary)
            Button("Mit \(request.url.scheme == "https" ? "HTTP" : "HTTPS") erneut öffnen") {
                var parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
                parts?.scheme = request.url.scheme == "https" ? "http" : "https"
                if let url = parts?.url { detail = nil; restart(url) }
            }
        }
    }
    private func lookup() async {
        guard state.duration > 0 else { return }
        state.segments = IntroSkipService.chapterSegments(state.chapters, duration: state.duration)
        state.skipStatus = "Suche nach Intro- und Recap-Zeiten …"
        var proposed = request
        proposed.contentID = contentID; proposed.season = Int(season); proposed.episode = Int(episode)
        let value = await IntroSkipService.identify(proposed)
        guard !Task.isCancelled else { return }
        identity = value; contentID = value.contentID; season = value.season.map(String.init) ?? ""; episode = value.episode.map(String.init) ?? ""
        let segments = await IntroSkipService.segments(contentID: value.contentID, season: value.season, episode: value.episode, duration: state.duration, isAnime: value.isAnime, chapters: state.chapters) { partial in
            if !Task.isCancelled { state.segments = partial }
        }
        guard !Task.isCancelled else { return }
        state.segments = segments
        state.skipStatus = segments.isEmpty ? "Keine passenden Zeitmarken verfügbar oder Dienst nicht erreichbar." : "\(segments.count) Abschnitte gefunden."
    }
    private func automatic(_ segment: SkipSegment) -> Bool { switch segment.kind { case .intro: return autoIntro; case .recap: return autoRecap; case .outro: return autoOutro } }
    private func updatePlaybackControls() {
        let idle = Date().timeIntervalSince(interaction) > hideSeconds
        let playing = !state.paused && !state.buffering && state.duration > 0
        if controls && panel == nil && detail == nil && playing && idle { controls = false; focus = .screen }
        if let segment = state.currentSegment, !skipped.contains(segment.id), automatic(segment) {
            skipped.insert(segment.id); state.seek(segment.end)
        }
    }
    private func touch() { interaction = Date() }
    private func reveal() { controls = true; focus = .play; touch() }
    private func restoreAfterMenu() {
        // Let tvOS restore focus to the button that presented the menu.
        // A second Back may already have hidden controls during dismissal.
        touch()
    }
    private func restart(_ url: URL) {
        guard !closing else { return }; closing = true
        let replacement = PlaybackRequest(url: url, title: request.title, contentID: contentID, season: Int(season), episode: Int(episode), isAnime: request.isAnime, start: state.position, subtitle: request.subtitle, successCallback: request.successCallback)
        let replace = {
            if replacing { dismiss(); return }
            request = replacement; identity = nil
            state.buffering = true; state.duration = 0; state.segments = []; state.animeActive = false
            state.speed = 1; scrubPosition = nil; skipped = []; closing = false; reveal()
        }
        if let controller = state.controller { controller.shutdown(completion: replace) } else { replace() }
    }
    private func close() {
        commitScrub()
        guard !closing else { return }; closing = true
        if let controller = state.controller {
            controller.finishPlayback { position, loaded in
                if !replacing { playbackReturn.prepare(request, position: position, loaded: loaded) }
                dismiss()
            }
        } else { dismiss() }
    }
    private func clock(_ seconds: Double) -> String { let n = Int(max(0, seconds)); return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%d:%02d", n / 60, n % 60) }
    private func panelTitle(_ value: Panel) -> String { switch value { case .speed: return "Wiedergabetempo"; case .anime: return "Anime4K"; case .audio: return "Audiosprache"; case .subtitles: return "Untertitel" } }
    private func applyAnime() {
        let mode = preset == "auto" ? ((identity ?? request).isAnime ? savedAnimeMode : "off") : preset
        state.controller?.anime(mode, tier: animeTier, protection: animeProtection)
    }
    private func scrub(_ direction: Int) {
        guard state.duration > 0 else { return }
        if !state.paused { state.skip(Double(direction * seekSeconds)); return }
        let now = Date()
        scrubRepeats = direction == scrubDirection && now.timeIntervalSince(lastScrubMove) < 0.65 ? scrubRepeats + 1 : 0
        scrubDirection = direction; lastScrubMove = now
        let multiplier = scrubRepeats >= 8 ? 4 : (scrubRepeats >= 3 ? 2 : 1)
        scrubPosition = min(state.duration, max(0, (scrubPosition ?? state.position) + Double(direction * seekSeconds * multiplier)))
    }
    private func commitScrub() {
        if let target = scrubPosition { state.seek(target) }
        scrubPosition = nil; scrubRepeats = 0
    }
}

private struct TVTimelineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.focusEffectDisabled() }
}

private struct TVPlaybackButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 27, weight: .medium))
            .frame(width: 62, height: 62)
            .foregroundStyle(focused ? Color.black : Color.white)
            .background(focused ? Color.white : Color.clear, in: Circle())
            .tvGlass(31).focusEffectDisabled()
            .scaleEffect(focused ? 1.12 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: focused)
    }
}
