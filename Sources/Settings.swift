import AppKit
import ScreenSaver

struct ScreensaverSettings: Equatable {
    static let moduleName = "ink.space4.Splatoon3Screensaver"

    var fpsCap: Int
    var renderScale: Float
    var paletteMode: Int
    var paletteCycleSeconds: Int
    var customWarm: NSColor
    var customCool: NSColor

    static var registeredDefaults: [String: Any] {
        [
            "fpsCap": 60,
            "renderScale": 1.0,
            "paletteMode": 0,
            "paletteCycleSeconds": 60,
            "customWarm": "#BAFF0A",
            "customCool": "#1D0AFF"
        ]
    }

    static func makeDefaults() -> ScreenSaverDefaults? {
        guard let defaults = ScreenSaverDefaults(forModuleWithName: moduleName) else {
            AppLog.renderer.fault("Could not create ScreenSaverDefaults for \(moduleName, privacy: .public)")
            return nil
        }
        defaults.register(defaults: registeredDefaults)
        return defaults
    }

    static func load() -> ScreensaverSettings {
        guard let d = makeDefaults() else {
            return ScreensaverSettings(
                fpsCap: registeredDefaults["fpsCap"] as? Int ?? 60,
                renderScale: registeredDefaults["renderScale"] as? Float ?? 1.0,
                paletteMode: registeredDefaults["paletteMode"] as? Int ?? 0,
                paletteCycleSeconds: registeredDefaults["paletteCycleSeconds"] as? Int ?? 60,
                customWarm: NSColor(hex: registeredDefaults["customWarm"] as? String ?? "#BAFF0A"),
                customCool: NSColor(hex: registeredDefaults["customCool"] as? String ?? "#1D0AFF")
            )
        }
        let storedCycleSeconds = d.integer(forKey: "paletteCycleSeconds")
        return ScreensaverSettings(
            fpsCap: d.integer(forKey: "fpsCap"),
            renderScale: max(0.5, min(1.5, d.float(forKey: "renderScale"))),
            paletteMode: d.integer(forKey: "paletteMode"),
            paletteCycleSeconds: [30, 60, 90, 120].contains(storedCycleSeconds) ? storedCycleSeconds : 60,
            customWarm: NSColor(hex: d.string(forKey: "customWarm") ?? "#BAFF0A"),
            customCool: NSColor(hex: d.string(forKey: "customCool") ?? "#1D0AFF")
        )
    }

    func save() {
        guard let d = Self.makeDefaults() else { return }
        d.set(fpsCap, forKey: "fpsCap")
        d.set(renderScale, forKey: "renderScale")
        d.set(paletteMode, forKey: "paletteMode")
        d.set(paletteCycleSeconds, forKey: "paletteCycleSeconds")
        d.set(customWarm.hexString, forKey: "customWarm")
        d.set(customCool.hexString, forKey: "customCool")
        d.synchronize()
    }

    static func == (lhs: ScreensaverSettings, rhs: ScreensaverSettings) -> Bool {
        lhs.fpsCap == rhs.fpsCap
            && lhs.renderScale == rhs.renderScale
            && lhs.paletteMode == rhs.paletteMode
            && lhs.paletteCycleSeconds == rhs.paletteCycleSeconds
            && lhs.customWarm.hexString == rhs.customWarm.hexString
            && lhs.customCool.hexString == rhs.customCool.hexString
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(cleaned, radix: 16) ?? 0xffffff
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255.0,
            green: CGFloat((value >> 8) & 0xff) / 255.0,
            blue: CGFloat(value & 0xff) / 255.0,
            alpha: 1.0
        )
    }

    var float3: SIMD3<Float> {
        let c = usingColorSpace(.deviceRGB) ?? self
        return SIMD3(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
    }

    var hexString: String {
        let c = usingColorSpace(.deviceRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int(round(c.redComponent * 255.0)),
            Int(round(c.greenComponent * 255.0)),
            Int(round(c.blueComponent * 255.0))
        )
    }
}
