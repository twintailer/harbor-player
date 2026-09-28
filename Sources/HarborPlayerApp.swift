import SwiftUI
import CoreText

@main
struct HarborPlayerApp: App {
    @State private var request: PlaybackRequest?
    @State private var pending: PlaybackRequest?
    @State private var address = ""
    @State private var error: String?
    init() {
        if let folder = Bundle.main.url(forResource: "Fonts", withExtension: nil),
           let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for url in urls where ["ttf", "otf"].contains(url.pathExtension) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
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
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Mit Stremio verbinden", systemImage: "link").font(.headline)
                            Text("In Stremio Web unter Einstellungen → Player → Externer Player „Outplayer“ auswählen. Harbor nimmt dessen Links entgegen. Outplayer selbst sollte dafür nicht installiert sein, da iOS bei gleichen URL-Schemas die Ziel-App nicht zuverlässig auswählt.")
                            Text("Falls ein HTTP-Stream als HTTPS geöffnet wird: im Player-Menü auf HTTP wechseln. Alternativ die originale Stream-URL hier einfügen.")
                            Text("Intro-Erkennung benötigt Kapitel oder eine Medien-ID und Episode. Diese kannst du während der Wiedergabe im Info-Menü ergänzen.")
                        }.font(.subheadline).foregroundStyle(.secondary)
                        Text("Anime4K • MKV • ASS-Untertitel").font(.caption).foregroundStyle(.mint)
                    }.padding(28).frame(maxWidth: 650)
                }.frame(maxWidth: .infinity).background(Color(red: 0.035, green: 0.055, blue: 0.075))
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in open(url) }
            .fullScreenCover(item: $request, onDismiss: {
                if let next = pending { pending = nil; request = next }
            }) { value in PlayerScreen(request: value) }
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
            if request != nil { pending = next; request = nil } else { request = next }
        } catch { self.error = error.localizedDescription }
    }
}
