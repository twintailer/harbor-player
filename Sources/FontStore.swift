import Foundation
import CoreText

enum FontStore {
    static var directory: URL {
        #if os(tvOS)
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Fonts")
        #else
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fonts")
        #endif
    }
    static func prepare() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let bundled = Bundle.main.url(forResource: "Inter", withExtension: "ttf", subdirectory: "Fonts") {
            let target = directory.appendingPathComponent("Inter.ttf")
            if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: bundled, to: target) }
        }
        if let fonts = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in fonts where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}
