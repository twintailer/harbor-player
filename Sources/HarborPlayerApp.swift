import SwiftUI
import CoreText

@main
struct HarborPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var playbackReturn = PlaybackReturn()
    @State private var request: PlaybackRequest?
    @State private var pending: PlaybackRequest?
    @State private var address = ""
    @State private var error: String?
    @State private var testLinkConsumed = false
    @State private var showPreferences = false
    init() {
        FontStore.prepare()
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        Image(systemName: "play.rectangle.fill").font(.system(size: 64)).foregroundStyle(.mint).padding(.top, 40)
                        Text("Harbor Player").font(.largeTitle.bold())
                        Text("Dein Stream. Dein Bild.").font(.title2).foregroundStyle(.secondary)
                        TextField("https:// …", text: $address).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("streamURL")
                        Button { openText() } label: { Label("Stream abspielen", systemImage: "play.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).tint(.mint).accessibilityIdentifier("openStream")
                        Button { showPreferences = true } label: { Label("Sprachen & Bedienung", systemImage: "slider.horizontal.3") }
                        if let message = playbackReturn.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        if playbackReturn.retryURL != nil { Button("Position erneut an Stremio übergeben") { playbackReturn.retry() } }
                        #if DEBUG
                        if ProcessInfo.processInfo.environment["HARBOR_TEST_CAPTURE_CALLBACK"] == "1", let callback = playbackReturn.lastCallback {
                            Text(callback.absoluteString).font(.caption).accessibilityIdentifier("returnCallback")
                        }
                        #endif
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Mit Stremio verbinden", systemImage: "link").font(.headline)
                            Text("In der Stremio-App als externen Player „Infuse“ auswählen. Harbor übernimmt die gespeicherte Position und gibt sie beim Schließen an Stremio zurück, wenn deine Stremio-Version diese Daten übergibt. Infuse selbst darf nicht parallel installiert sein, da beide Apps dieselben Links öffnen.")
                            Text("VLC- und Outplayer-Links funktionieren weiterhin, übertragen von Stremio aber keine Abspielposition. Für die Synchronisierung bitte Infuse auswählen.")
                            Text("Falls ein HTTP-Stream als HTTPS geöffnet wird: im Player-Menü auf HTTP wechseln. Alternativ die originale Stream-URL hier einfügen.")
                            Text("Intro-Erkennung benötigt Kapitel oder eine Medien-ID und Episode. Diese kannst du während der Wiedergabe im Info-Menü ergänzen.")
                        }.font(.subheadline).foregroundStyle(.secondary)
                        Text("Anime4K • MKV • ASS-Untertitel").font(.caption).foregroundStyle(.mint)
                    }.padding(28).frame(maxWidth: 650)
                }.frame(maxWidth: .infinity).background(Color(red: 0.035, green: 0.055, blue: 0.075))
            }
            .preferredColorScheme(.dark)
            .environmentObject(playbackReturn)
            .sheet(isPresented: $showPreferences) {
                NavigationStack { Form { LanguagePreferencesView() }.navigationTitle("Einstellungen").toolbar { Button("Fertig") { showPreferences = false } } }.preferredColorScheme(.dark)
            }
            .onAppear {
                #if DEBUG
                if !testLinkConsumed, let raw = ProcessInfo.processInfo.environment["HARBOR_TEST_STREAM_URL"], let url = URL(string: raw) {
                    testLinkConsumed = true; open(url)
                }
                #endif
            }
            .onOpenURL { url in open(url) }
            .fullScreenCover(item: $request, onDismiss: {
                PlaybackOrientation.setPlaying(false)
                playbackReturn.deliverPending()
                if let next = pending { pending = nil; request = next }
            }) { value in PlayerScreen(request: value).environmentObject(playbackReturn) }
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
            if request != nil {
                pending = next
                NotificationCenter.default.post(name: .harborReplacePlayback, object: nil)
            } else { request = next }
        } catch { self.error = error.localizedDescription }
    }
}

extension Notification.Name {
    static let harborReplacePlayback = Notification.Name("harborReplacePlayback")
}
