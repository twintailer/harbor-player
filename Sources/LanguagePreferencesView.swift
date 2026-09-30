import SwiftUI

struct LanguagePreferencesView: View {
    @AppStorage("preferredAudio") private var audio = TrackPreferences.systemLanguage
    @AppStorage("preferredSubtitles") private var subtitles = TrackPreferences.systemLanguage
    @AppStorage("preferForced") private var forced = true
    @AppStorage("seekSeconds") private var seekSeconds = 15
    var body: some View {
        Section("Bevorzugte Sprachen") {
            languagePicker("Audio", value: $audio)
            languagePicker("Untertitel", value: $subtitles)
            Toggle("Forced bevorzugen", isOn: $forced)
            Text(forced ? "Bei bevorzugter Audiosprache: Forced-Untertitel. Bei anderer Audiosprache: vollständige Untertitel in deiner bevorzugten Untertitelsprache. Fehlt die passende Spur, werden keine fremdsprachigen Untertitel erzwungen." : "Vollständige Untertitel in der bevorzugten Untertitelsprache.").font(.footnote).foregroundStyle(.secondary)
        }
        Section("Sprungtasten") {
            Picker("Sprungweite", selection: $seekSeconds) {
                ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) Sekunden").tag($0) }
            }
            #if os(tvOS)
            Text("Bei ausgeblendeter Bedienleiste: Links zurück, Rechts vor. Die Zeitleiste lässt sich ebenfalls mit Links/Rechts bedienen.").font(.footnote).foregroundStyle(.secondary)
            #else
            Text("Links doppeltippen: zurück. Rechts doppeltippen: vor.").font(.footnote).foregroundStyle(.secondary)
            #endif
        }
    }
    private func languagePicker(_ label: String, value: Binding<String>) -> some View {
        Picker(label, selection: value) {
            ForEach(TrackPreferences.languages, id: \.self) { code in
                Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
            }
        }
    }
}
