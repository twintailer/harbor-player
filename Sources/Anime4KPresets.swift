import Foundation

enum Anime4KPresets {
    static let modes = ["A", "B", "C", "AA", "BB", "CA"]
    static func label(_ mode: String) -> String {
        switch mode {
        case "auto": return "Auto · gespeicherter Modus"
        case "off": return "Aus"
        case "fast": return "Schnell · DTD"
        case "B": return "Modus B · Soft restore + upscale"
        case "C": return "Modus C · Denoise + upscale"
        case "AA": return "Modus A+A · Double restore"
        case "BB": return "Modus B+B · Double soft restore"
        case "CA": return "Modus C+A · Denoise + restore"
        case "hq": return "Hohe Qualität · Modus A"
        default: return "Modus A · Restore + upscale"
        }
    }
    static func shaders(_ mode: String, tier: String = "balanced") -> [String] {
        if mode == "off" { return [] }
        if mode == "fast" || tier == "fast" { return ["Anime4K_Upscale_DTD_x2"] }
        let mode = mode == "hq" ? "A" : mode
        let quality = tier == "hq"
        let size = quality ? "VL" : "S"
        let clamp = "Anime4K_Clamp_Highlights"
        let restore = "Anime4K_Restore_CNN_" + size
        let soft = "Anime4K_Restore_CNN_Soft_" + size
        let upscale = "Anime4K_Upscale_CNN_x2_" + size
        let denoise = "Anime4K_Upscale_Denoise_CNN_x2_" + size
        let down2 = "Anime4K_AutoDownscalePre_x2", down4 = "Anime4K_AutoDownscalePre_x4"
        let final = "Anime4K_Upscale_CNN_x2_M"
        if !quality {
            switch mode {
            case "B": return [soft, upscale]
            case "C": return [denoise]
            case "AA": return [clamp, restore, upscale, restore]
            case "BB": return [clamp, soft, upscale, soft]
            case "CA": return [denoise, restore]
            default: return [restore, upscale]
            }
        }
        switch mode {
        case "B": return [clamp, soft, upscale, down2, down4, final]
        case "C": return [clamp, denoise, down2, down4, final]
        case "AA": return [clamp, restore, upscale, "Anime4K_Restore_CNN_M", down2, down4, final]
        case "BB": return [clamp, soft, upscale, down2, "Anime4K_Restore_CNN_Soft_M", down4, final]
        case "CA": return [clamp, denoise, down2, down4, "Anime4K_Restore_CNN_M", final]
        default: return [clamp, restore, upscale, down2, down4, final]
        }
    }
}
