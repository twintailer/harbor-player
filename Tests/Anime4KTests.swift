import Foundation

@main struct Anime4KTests {
    static func main() {
        for tier in ["balanced", "hq"] {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Anime4K")
            for mode in Anime4KPresets.modes {
                let shaders = Anime4KPresets.shaders(mode, tier: tier)
                precondition(!shaders.isEmpty)
                for shader in shaders { precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent(shader + ".glsl").path), "Missing bundled shader: \(shader)") }
            }
        }
        precondition(Anime4KPresets.shaders("AA").filter { $0 == "Anime4K_Restore_CNN_S" }.count == 2)
        precondition(Anime4KPresets.shaders("BB").filter { $0 == "Anime4K_Restore_CNN_Soft_S" }.count == 2)
        precondition(Anime4KPresets.shaders("CA") == ["Anime4K_Upscale_Denoise_CNN_x2_S", "Anime4K_Restore_CNN_S"])
        precondition(Anime4KPresets.shaders("BB", tier: "hq").contains("Anime4K_Restore_CNN_Soft_M"))
        precondition(Anime4KPresets.shaders("off").isEmpty)
        print("All six Anime4K modes and both quality tiers have complete bundled chains")
    }
}
