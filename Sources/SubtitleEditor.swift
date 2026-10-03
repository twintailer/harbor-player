import SwiftUI

struct SubtitleEditor: View {
    @Binding var style: SubtitleSettings
    @Binding var importFont: Bool
    var body: some View {
        Section("Harbor-Untertitelstil") {
            Text("So sehen deine Untertitel aus").font(.custom(style.font, size: min(40, style.size))).bold(style.bold).foregroundStyle(color(style.color).opacity(style.opacity)).padding().frame(maxWidth: .infinity).background(style.style == "box" ? color(style.boxColor).opacity(style.boxOpacity) : .black).shadow(color: color(style.borderColor), radius: style.style == "shadow" ? 2 : 0)
            Picker("Hintergrund", selection: $style.style) { Text("Schatten").tag("shadow"); Text("Umrandung").tag("outline"); Text("Balken").tag("box") }
            Picker("ASS-Stil", selection: $style.ass) { Text("Mein Stil").tag("strip"); Text("Original").tag("no"); Text("Nur Größe").tag("scale") }
            Picker("Schrift", selection: $style.font) {
                ForEach(Array(Set(["Inter", "Helvetica Neue", "Arial Rounded MT Bold", "Georgia", "Geeza Pro", style.font])).sorted(), id: \.self) { Text($0).tag($0) }
            }
            Button("Eigene Schrift importieren (TTF/OTF)") { importFont = true }
            Toggle("Fett", isOn: $style.bold)
            slider("Größe", value: $style.size, range: 16...120, step: 1)
            slider("Zeilenabstand", value: Binding(get: { style.lineSpacing ?? 0 }, set: { style.lineSpacing = $0 }), range: -10...30, step: 1)
            slider("Deckkraft", value: $style.opacity, range: 0.2...1, step: 0.05)
            slider("Abstand unten (%)", value: $style.margin, range: 0...100, step: 1)
            Picker("Ausrichtung", selection: $style.alignment) { Text("Links").tag("left"); Text("Mitte").tag("center"); Text("Rechts").tag("right") }
            ColorPicker("Textfarbe", selection: colorBinding($style.color), supportsOpacity: false)
            ColorPicker("Konturfarbe", selection: colorBinding($style.borderColor), supportsOpacity: false)
            slider("Konturstärke", value: $style.borderSize, range: 0...6, step: 1)
            if style.style == "box" {
                ColorPicker("Balkenfarbe", selection: colorBinding($style.boxColor), supportsOpacity: false)
                slider("Balken-Deckkraft", value: $style.boxOpacity, range: 0.2...1, step: 0.05)
            }
            Stepper("Versatz: \(style.delay, specifier: "%.1f") s", value: $style.delay, in: -60...60, step: 0.1)
            Button("Harbor-Standard wiederherstellen") { style = SubtitleSettings() }
        }
    }
    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading) { HStack { Text(label); Spacer(); Text(String(format: "%g", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }; Slider(value: value, in: range, step: step) }
    }
    private func color(_ value: String) -> Color {
        let hex = UInt32(value.dropFirst(), radix: 16) ?? 0xFFFFFF
        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    private func colorBinding(_ value: Binding<String>) -> Binding<Color> {
        Binding(get: { color(value.wrappedValue) }, set: { new in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(new).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            value.wrappedValue = String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        })
    }
}
