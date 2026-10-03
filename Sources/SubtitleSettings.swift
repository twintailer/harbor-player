import Foundation

struct SubtitleSettings: Codable, Equatable {
    var style = "shadow"
    var font = "Inter"
    var size = 32.0
    var bold = false
    var opacity = 1.0
    var margin = 12.0
    var alignment = "center"
    var color = "#FFFFFF"
    var borderColor = "#000000"
    var borderSize = 0.0
    var boxColor = "#000000"
    var boxOpacity = 0.6
    var ass = "strip"
    var delay = 0.0
    // Optional so saved settings from earlier versions decode unchanged.
    var lineSpacing: Double? = nil

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "subtitleStyle"),
              let result = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return result
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "subtitleStyle") }
    static func mpvColor(_ hex: String, alpha: Double) -> String {
        let rgb = String(hex.dropFirst()).uppercased()
        let valid = hex.hasPrefix("#") && rgb.count == 6 && rgb.allSatisfy { $0.isHexDigit }
        return String(format: "#%02X%@", Int(min(1, max(0, alpha)) * 255), valid ? rgb : "FFFFFF")
    }
    var options: [String: String] {
        let forceStyle = ass == "strip" || ass == "force"
        var values = [
            "sub-font": font, "sub-font-size": "32", "sub-scale": String(size / 32),
            "sub-bold": bold ? "yes" : "no", "sub-color": Self.mpvColor(color, alpha: opacity),
            "sub-border-color": Self.mpvColor(borderColor, alpha: opacity),
            "sub-pos": String(100 - margin), "sub-margin-y": "0", "sub-align-x": alignment,
            "sub-ass-override": forceStyle ? "strip" : ass, "embeddedfonts": forceStyle ? "no" : "yes",
            "sub-ass-use-video-data": forceStyle ? "none" : "all",
            "sub-ass-force-margins": ass == "no" ? "no" : "yes",
            "sub-line-spacing": String(lineSpacing ?? 0),
            "sub-delay": String(delay), "sub-use-margins": ass == "no" ? "no" : "yes"
        ]
        values["sub-border-style"] = style == "box" ? "background-box" : "outline-and-shadow"
        values["sub-border-size"] = String(style == "outline" ? max(1, borderSize) : (style == "box" ? 0 : borderSize))
        values["sub-shadow-offset"] = style == "shadow" ? "1.4" : "0"
        values["sub-back-color"] = style == "box" ? Self.mpvColor(boxColor, alpha: boxOpacity * opacity) : Self.mpvColor("#000000", alpha: style == "shadow" ? opacity : 0)
        return values
    }
}
