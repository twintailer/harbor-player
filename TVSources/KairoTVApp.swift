import SwiftUI

@main struct KairoTVApp: App {
    @StateObject private var playbackReturn = PlaybackReturn()
    @State private var request: PlaybackRequest?
    @State private var pending: PlaybackRequest?
    @State private var address = ""
    @State private var error: String?
    @State private var preferences = false
    @State private var consumedTestLink = false
    init() {
        FontStore.prepare()
        #if DEBUG
        assert(FileManager.default.fileExists(atPath: FontStore.directory.appendingPathComponent("Inter.ttf").path), "Bundled subtitle font must be writable in the tvOS cache")
        #endif
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(alignment: .leading, spacing: 28) {
                    Label("Kairo Player", systemImage: "play.rectangle.fill").font(.system(size: 54, weight: .bold))
                    Text("Dein Stream. Dein Bild.").font(.title2).foregroundStyle(.secondary)
                    TextField("Stream-URL", text: $address).accessibilityIdentifier("streamURL")
                    HStack(spacing: 30) {
                        Button("Stream abspielen") { openText() }.accessibilityIdentifier("openStream")
                        Button("Einstellungen") { preferences = true }
                    }
                    Text("In Stremio als externen Player „Infuse“ auswählen. Kairo übernimmt Stream und Abspielposition, wenn Stremio diese übergibt. Die originale Infuse-App darf nicht gleichzeitig installiert sein.").font(.callout).foregroundStyle(.secondary)
                    Text("Play/Pause: Wiedergabe steuern · Auswahl: Bedienleiste öffnen · Links/Rechts bei ausgeblendeter Leiste: springen · Zurück: Leiste schließen, danach Player verlassen.").font(.callout).foregroundStyle(.secondary)
                    if let message = playbackReturn.message { Text(message).font(.footnote) }
                    if playbackReturn.retryURL != nil { Button("Position erneut an Stremio übergeben") { playbackReturn.retry() } }
                    #if DEBUG
                    if let callback = playbackReturn.lastCallback, ProcessInfo.processInfo.environment["HARBOR_TEST_CAPTURE_CALLBACK"] == "1" {
                        Text(callback.absoluteString).font(.footnote).accessibilityIdentifier("returnCallback")
                    }
                    #endif
                    Text("Anime4K · MKV · ASS-Untertitel · Intro & Recap").foregroundStyle(.secondary)
                }.padding(70).frame(maxWidth: 1400).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.035))
            }.preferredColorScheme(.dark).tint(.white)
                .environmentObject(playbackReturn)
                .sheet(isPresented: $preferences) { TVPreferences() }
                .onOpenURL { open($0) }
                .onAppear {
                    #if DEBUG
                    if !consumedTestLink, let raw = ProcessInfo.processInfo.environment["HARBOR_TEST_STREAM_URL"], let url = URL(string: raw) {
                        consumedTestLink = true; open(url)
                    }
                    #endif
                }
                .fullScreenCover(item: $request, onDismiss: {
                    playbackReturn.deliverPending()
                    if let next = pending { pending = nil; request = next }
                }) { TVPlayerScreen(request: $0).environmentObject(playbackReturn) }
                .alert("Stream öffnen", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func openText() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { error = "Ungültige URL"; return }
        open(url)
    }
    private func open(_ url: URL) {
        do {
            let next = try PlaybackRequest.parse(url)
            if request != nil { pending = next; NotificationCenter.default.post(name: .harborReplacePlayback, object: nil) }
            else { request = next }
        } catch { self.error = error.localizedDescription }
    }
}

extension Notification.Name { static let harborReplacePlayback = Notification.Name("harborReplacePlayback") }

struct TVGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 32
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency { content.background(Color(white: 0.13), in: shape) }
        else { content.glassEffect(.regular.tint(.black.opacity(0.24)), in: shape) }
    }
}
extension View { func tvGlass(_ radius: CGFloat = 32) -> some View { modifier(TVGlass(radius: radius)) } }
