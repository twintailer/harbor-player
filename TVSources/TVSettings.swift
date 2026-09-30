import SwiftUI
import CoreText

struct TVSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button("Fertig") { dismiss() }.accessibilityIdentifier("closeSettings")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) { content() }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("settingsScroll")
        }.padding(45).frame(maxWidth: 1100, maxHeight: 850).tvGlass(44).padding(50)
            .preferredColorScheme(.dark).tint(.white).presentationBackground(.clear)
            .onExitCommand { dismiss() }
    }
}

struct TVPreferences: View {
    @AppStorage("controlsHideSeconds") private var hideSeconds = 6.0
    @AppStorage("autoSkipIntro") private var intro = false
    @AppStorage("autoSkipRecap") private var recap = false
    @AppStorage("autoSkipOutro") private var outro = false
    var body: some View {
        TVSheet(title: "Sprachen & Bedienung") {
            LanguagePreferencesView()
            TVNumberSetting(title: "Leiste ausblenden nach (Sekunden)", value: $hideSeconds, range: 3...30, step: 1)
            Toggle("Intro automatisch überspringen", isOn: $intro)
            Toggle("Recap automatisch überspringen", isOn: $recap)
            Toggle("Abspann automatisch überspringen", isOn: $outro)
            Text("Lautstärke steuerst du über die Lautstärketasten der Siri Remote. Die Bildhelligkeit stellst du am Fernseher ein.").font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct TVNumberSetting: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var body: some View {
        HStack(spacing: 22) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Button { value = max(range.lowerBound, value - step) } label: { Image(systemName: "minus").frame(width: 35) }
                .accessibilityLabel(title + " verringern")
            Text(String(format: "%g", value)).monospacedDigit().frame(width: 90)
            Button { value = min(range.upperBound, value + step) } label: { Image(systemName: "plus").frame(width: 35) }
                .accessibilityLabel(title + " erhöhen")
        }.focusSection()
    }
}

struct TVSubtitleSettings: View {
    @Binding var style: SubtitleSettings
    let controller: PlayerController?
    @State private var subtitleURL = ""
    @State private var fontURL = ""
    @State private var importing = false
    @State private var message: String?
    var body: some View {
        TVSheet(title: "Untertitel gestalten") {
            Text("So sehen deine Untertitel aus").font(.custom(style.font, size: min(60, style.size))).bold(style.bold)
                .foregroundStyle(color(style.color).opacity(style.opacity)).padding(30).frame(maxWidth: .infinity)
                .background(style.style == "box" ? color(style.boxColor).opacity(style.boxOpacity) : .black)
                .shadow(color: color(style.borderColor), radius: style.style == "shadow" ? 2 : 0)
            Picker("Hintergrund", selection: $style.style) { Text("Schatten").tag("shadow"); Text("Umrandung").tag("outline"); Text("Balken").tag("box") }
            Picker("ASS-Stil", selection: $style.ass) { Text("Mein Stil").tag("strip"); Text("Original").tag("no"); Text("Nur Größe").tag("scale") }
            Picker("Schrift", selection: $style.font) {
                ForEach(Array(Set(["Inter", "Helvetica Neue", "Arial Rounded MT Bold", "Georgia", "Geeza Pro", style.font])).sorted(), id: \.self) { Text($0).tag($0) }
            }
            Toggle("Fett", isOn: $style.bold)
            TVNumberSetting(title: "Größe", value: $style.size, range: 16...120, step: 1)
            TVNumberSetting(title: "Deckkraft", value: $style.opacity, range: 0.2...1, step: 0.05)
            TVNumberSetting(title: "Abstand unten (%)", value: $style.margin, range: 0...100, step: 1)
            Picker("Ausrichtung", selection: $style.alignment) { Text("Links").tag("left"); Text("Mitte").tag("center"); Text("Rechts").tag("right") }
            palette("Textfarbe", value: $style.color)
            palette("Konturfarbe", value: $style.borderColor)
            TVNumberSetting(title: "Konturstärke", value: $style.borderSize, range: 0...6, step: 1)
            if style.style == "box" {
                palette("Balkenfarbe", value: $style.boxColor)
                TVNumberSetting(title: "Balken-Deckkraft", value: $style.boxOpacity, range: 0.2...1, step: 0.05)
            }
            TVNumberSetting(title: "Untertitelversatz (Sekunden)", value: $style.delay, range: -60...60, step: 0.1)
            TextField("Externe Untertitel-URL (SRT / ASS / VTT)", text: $subtitleURL)
            Button("Untertitel-URL laden") {
                if let url = URL(string: subtitleURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { controller?.addSubtitle(url.absoluteString); message = "Untertitel an den Player übergeben." }
                else { message = "Bitte eine gültige HTTP(S)-URL eingeben." }
            }
            TextField("Eigene Schrift-URL (TTF / OTF)", text: $fontURL)
            Button(importing ? "Schrift wird geladen …" : "Eigene Schrift laden") { Task { await importFont() } }.disabled(importing)
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            Button("Standard wiederherstellen") { style = SubtitleSettings() }
        }
    }
    private func palette(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(title, selection: value) {
                ForEach([("Weiß", "#FFFFFF"), ("Schwarz", "#000000"), ("Gelb", "#FFFF00"), ("Rot", "#FF4040"), ("Blau", "#4080FF"), ("Grün", "#40FF80")], id: \.1) { Text($0.0).tag($0.1) }
                if !["#FFFFFF", "#000000", "#FFFF00", "#FF4040", "#4080FF", "#40FF80"].contains(value.wrappedValue) { Text("Eigene Farbe").tag(value.wrappedValue) }
            }
            TextField(title + " als #RRGGBB", text: value)
        }
    }
    private func color(_ hex: String) -> Color {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        return Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
    @MainActor private func importFont() async {
        guard !importing, let url = URL(string: fontURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { message = "Bitte eine gültige HTTP(S)-Schrift-URL eingeben."; return }
        importing = true; defer { importing = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 30_000_000,
                  let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider), let name = font.postScriptName else { throw PlaybackRequest.RequestError.invalidURL }
            let target = FontStore.directory.appendingPathComponent(UUID().uuidString + ".ttf")
            try data.write(to: target, options: .atomic)
            CTFontManagerRegisterFontsForURL(target as CFURL, .process, nil)
            controller?.property("sub-fonts-dir", FontStore.directory.path)
            style.font = name as String
            message = "Schrift geladen: \(style.font)"
        } catch { message = "Schrift konnte nicht geladen werden: \(error.localizedDescription)" }
    }
}
