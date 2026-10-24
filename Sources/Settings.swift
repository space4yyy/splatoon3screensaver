import AppKit
import ScreenSaver

enum PaletteMode: Int, CaseIterable {
    case random
    case cycle
    case splatoon1
    case splatoon2
    case splatoon3
    case custom
}

struct ScreensaverSettings: Equatable {
    static let moduleName = "ink.space4.Splatoon3Screensaver"

    /// Frame rate caps offered in the options sheet; 0 matches the display.
    static let fpsOptions = [30, 60, 120, 0]
    static let paletteCycleOptions = [30, 60, 90, 120]
    /// 0 = random workshop seed, 1-6 = workshop seed, 7 = procedural.
    static let seedIndices = 0...7
    /// Frame rate used while the battery saver is engaged.
    static let batterySaverFPS = 30

    var fpsCap: Int
    var batterySaver: Bool
    var paletteMode: PaletteMode
    var paletteCycleSeconds: Int
    var customWarm: NSColor
    var customCool: NSColor
    var seedIndex: Int

    /// Custom ink defaults are Splatoon 3's inks as they appear on screen.
    static let standard = ScreensaverSettings(
        fpsCap: 60,
        batterySaver: true,
        paletteMode: .random,
        paletteCycleSeconds: 60,
        customWarm: NSColor(hex: "#DEFF38"),
        customCool: NSColor(hex: "#5F38FF"),
        seedIndex: 0
    )

    static var registeredDefaults: [String: Any] {
        [
            "fpsCap": standard.fpsCap,
            "batterySaver": standard.batterySaver,
            "paletteMode": standard.paletteMode.rawValue,
            "paletteCycleSeconds": standard.paletteCycleSeconds,
            "customWarm": standard.customWarm.hexString,
            "customCool": standard.customCool.hexString,
            "seedIndex": standard.seedIndex
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
        guard let d = makeDefaults() else { return standard }
        let fpsCap = d.integer(forKey: "fpsCap")
        let cycleSeconds = d.integer(forKey: "paletteCycleSeconds")
        let seedIndex = d.integer(forKey: "seedIndex")
        return ScreensaverSettings(
            fpsCap: fpsOptions.contains(fpsCap) ? fpsCap : standard.fpsCap,
            batterySaver: d.bool(forKey: "batterySaver"),
            paletteMode: PaletteMode(rawValue: d.integer(forKey: "paletteMode")) ?? standard.paletteMode,
            paletteCycleSeconds: paletteCycleOptions.contains(cycleSeconds) ? cycleSeconds : standard.paletteCycleSeconds,
            customWarm: d.string(forKey: "customWarm").map(NSColor.init(hex:)) ?? standard.customWarm,
            customCool: d.string(forKey: "customCool").map(NSColor.init(hex:)) ?? standard.customCool,
            seedIndex: seedIndices.contains(seedIndex) ? seedIndex : standard.seedIndex
        )
    }

    func save() {
        guard let d = Self.makeDefaults() else { return }
        d.set(fpsCap, forKey: "fpsCap")
        d.set(batterySaver, forKey: "batterySaver")
        d.set(paletteMode.rawValue, forKey: "paletteMode")
        d.set(paletteCycleSeconds, forKey: "paletteCycleSeconds")
        d.set(customWarm.hexString, forKey: "customWarm")
        d.set(customCool.hexString, forKey: "customCool")
        d.set(seedIndex, forKey: "seedIndex")
        d.removeObject(forKey: "renderScale")
        d.synchronize()
    }

    static func == (lhs: ScreensaverSettings, rhs: ScreensaverSettings) -> Bool {
        lhs.fpsCap == rhs.fpsCap
            && lhs.batterySaver == rhs.batterySaver
            && lhs.paletteMode == rhs.paletteMode
            && lhs.paletteCycleSeconds == rhs.paletteCycleSeconds
            && lhs.customWarm.hexString == rhs.customWarm.hexString
            && lhs.customCool.hexString == rhs.customCool.hexString
            && lhs.seedIndex == rhs.seedIndex
    }
}

extension NSColor {
    /// Parses `#RRGGBB` as an sRGB colour, the form custom inks are stored in.
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(cleaned, radix: 16) ?? 0xffffff
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255.0,
            green: CGFloat((value >> 8) & 0xff) / 255.0,
            blue: CGFloat(value & 0xff) / 255.0,
            alpha: 1.0
        )
    }

    /// An sRGB colour showing how linear-light shader values appear on screen.
    convenience init(linearRGB c: SIMD3<Float>) {
        func encode(_ v: Float) -> CGFloat {
            let v = min(max(v, 0), 1)
            return CGFloat(v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055)
        }
        self.init(srgbRed: encode(c.x), green: encode(c.y), blue: encode(c.z), alpha: 1.0)
    }

    private var srgbComponents: SIMD3<Float> {
        let c = usingColorSpace(.sRGB) ?? self
        return SIMD3(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
            .clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1))
    }

    /// Linear-light components. The image pass writes to an sRGB drawable, so
    /// these come out on screen as the colour the user picked.
    var linearRGB: SIMD3<Float> {
        let c = srgbComponents
        func decode(_ v: Float) -> Float {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return SIMD3(decode(c.x), decode(c.y), decode(c.z))
    }

    var hexString: String {
        let c = srgbComponents
        return String(
            format: "#%02X%02X%02X",
            Int((c.x * 255.0).rounded()),
            Int((c.y * 255.0).rounded()),
            Int((c.z * 255.0).rounded())
        )
    }
}
