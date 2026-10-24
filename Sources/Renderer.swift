import Foundation
import Metal
import OSLog
import QuartzCore

private struct SimUniforms {
    var frame: Int32
    var seedIndex: Int32
    var dateSeconds: Float
    var padding: Float = 0
}

private struct ImageUniforms {
    var coolTransform: SIMD4<Float>
    var warmTransform: SIMD4<Float>
    var bubbleOffset: SIMD4<Float>
    var warmBase: SIMD4<Float>
    var warmTint: SIMD4<Float>
    var coolBase: SIMD4<Float>
    var coolTint: SIMD4<Float>
}

enum AppLog {
    static let renderer = Logger(subsystem: ScreensaverSettings.moduleName, category: "renderer")
}

/// Ink colours from the original shader, in linear light. Indexed by palette
/// phase: 0 = Splatoon 3, 1 = Splatoon 1, 2 = Splatoon 2.
enum InkPalette {
    static let warm: [SIMD3<Float>] = [
        SIMD3(0.729412, 1.0, 0.039216),
        SIMD3(0.945098, 0.098039, 0.0),
        SIMD3(0.980392, 0.054902, 0.470588),
    ]
    static let cool: [SIMD3<Float>] = [
        SIMD3(0.113725, 0.039216, 1.0),
        SIMD3(0.0, 0.027451, 0.956863),
        SIMD3(0.039216, 0.921569, 0.031373),
    ]
    fileprivate static let warmTint: [SIMD3<Float>] = [
        SIMD3(0.113726, 0.0, 0.2),
        SIMD3(0.003922, 0.027451, 0.0),
        SIMD3(0.0, 0.019608, 0.086275),
    ]
    fileprivate static let coolTint: [SIMD3<Float>] = [
        SIMD3(0.031373, -0.003922, -0.019608),
        SIMD3(0.0, 0.05098, 0.003922),
        SIMD3(0.121569, 0.0, -0.003922),
    ]

    static func phase(for mode: PaletteMode) -> Int {
        switch mode {
        case .splatoon1: return 1
        case .splatoon2: return 2
        default: return 0
        }
    }
}

/// The palette colours for one frame. This replaces the original Buffer D,
/// whose phase is a pure function of time and palette mode.
private struct PaletteBlend {
    var warmBase: SIMD3<Float>
    var warmTint: SIMD3<Float>
    var coolBase: SIMD3<Float>
    var coolTint: SIMD3<Float>
}

private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

private func fract(_ x: Double) -> Double {
    x - x.rounded(.down)
}

private final class SplatoonSimulation {
    static let bufferWidth = 640
    static let bufferHeight = 360
    /// The original shader advances its fluid 60 times per second.
    private static let stepInterval = 1.0 / 60.0
    private static let maxStepsPerFrame = 4

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let resourceBundle: Bundle

    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var imagePipelines: [UInt: MTLRenderPipelineState] = [:]
    private var passDescriptors: [String: MTLRenderPassDescriptor] = [:]
    private var sampler: MTLSamplerState?
    private var library: MTLLibrary?
    private var bufferA: MTLTexture?
    private var bufferB: MTLTexture?
    private var bufferC: MTLTexture?
    private var dyeTexture: MTLTexture?
    private var bubbleMask: MTLTexture?
    private var seedTexture: MTLTexture?
    private var lastSeedIndex: Int = -1
    private var randomShaderSeed: Int = Int.random(in: 0...5)

    private var settings: ScreensaverSettings
    private var startTime = CACurrentMediaTime()
    private var lastAdvanceTime: CFTimeInterval?
    private var stepBacklog = 0.0
    private var lastSettingsCheckTime = 0.0
    private var frame: Int32 = 0
    private var resolvedPaletteMode: PaletteMode = .splatoon3
    private var customWarmRGB = SIMD3<Float>(0, 0, 0)
    private var customCoolRGB = SIMD3<Float>(0, 0, 0)
    private(set) var hasFatalError = false
    let key: UInt64
    private let lock = NSLock()

    init?(
        device: MTLDevice,
        resourceBundle: Bundle,
        screenID: String
    ) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.resourceBundle = resourceBundle
        self.key = device.registryID
        self.settings = ScreensaverSettings.load()
        AppLog.renderer.info("[Screen \(screenID, privacy: .public)] Shared simulation initialized, device=\(self.key), resourceBundle=\(resourceBundle.bundleURL.path, privacy: .public)")
        buildResources()
        bubbleMask = makeBubbleMaskTexture()
        if bubbleMask == nil {
            AppLog.renderer.error("[Screen \(screenID, privacy: .public)] Bubble mask texture was not loaded")
            hasFatalError = true
        }
        makeTextures()
        applySettingsLocked(settings, forceReset: true)
    }

    /// Re-reads settings. Only a new starting pattern restarts the fluid;
    /// colour and frame rate changes apply to the running animation.
    func reloadSettings(forceReset: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        applySettingsLocked(ScreensaverSettings.load(), forceReset: forceReset)
    }

    private func applySettingsLocked(_ latest: ScreensaverSettings, forceReset: Bool) {
        let previous = settings
        settings = latest
        customWarmRGB = latest.customWarm.linearRGB
        customCoolRGB = latest.customCool.linearRGB

        let reset = forceReset || latest.seedIndex != previous.seedIndex
        if reset {
            frame = 0
            startTime = CACurrentMediaTime()
            lastAdvanceTime = nil
            stepBacklog = 0
            lastSettingsCheckTime = 0
            randomShaderSeed = Int.random(in: 0...5)
        }

        if latest.paletteMode == .random {
            let games: [PaletteMode] = [.splatoon1, .splatoon2, .splatoon3]
            if reset || !games.contains(resolvedPaletteMode) {
                resolvedPaletteMode = games.randomElement() ?? .splatoon3
            } else if previous.paletteMode != .random {
                // Picking Random in the options sheet should visibly change the inks.
                resolvedPaletteMode = games.filter { $0 != resolvedPaletteMode }.randomElement() ?? .splatoon3
            }
        } else {
            resolvedPaletteMode = latest.paletteMode
        }

        AppLog.renderer.debug("Shared simulation settings applied, reset=\(reset), fps=\(latest.fpsCap), batterySaver=\(latest.batterySaver), palette=\(latest.paletteMode.rawValue), cycleSeconds=\(latest.paletteCycleSeconds), resolvedPalette=\(self.resolvedPaletteMode.rawValue), seed=\(latest.seedIndex)")
    }

    func makeCommandBuffer() -> MTLCommandBuffer? {
        queue.makeCommandBuffer()
    }

    /// Encodes the simulation steps that are due. Steps run on a fixed 60 Hz
    /// clock, so lower frame rates encode two steps per frame instead of slowing
    /// the ink down, and frames between steps (120 fps) encode nothing.
    func advance(commandBuffer: MTLCommandBuffer, now: CFTimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        if hasFatalError { return }
        if now - lastSettingsCheckTime >= 1.0 {
            lastSettingsCheckTime = now
            let latestSettings = ScreensaverSettings.load()
            if latestSettings != settings {
                applySettingsLocked(latestSettings, forceReset: false)
            }
        }

        if let lastAdvanceTime {
            stepBacklog += min(max(now - lastAdvanceTime, 0), 0.25)
        } else {
            stepBacklog = Self.stepInterval
        }
        lastAdvanceTime = now

        // A quarter step of slack keeps timer jitter from alternating between
        // zero and two steps when the frame rate matches the step rate.
        let dueSteps = Int((stepBacklog / Self.stepInterval + 0.25).rounded(.down))
        let steps = min(dueSteps, Self.maxStepsPerFrame)
        guard steps > 0 else { return }
        stepBacklog = steps == dueSteps ? stepBacklog - Double(steps) * Self.stepInterval : 0

        let shaderSeedIndex = settings.seedIndex == 0 ? randomShaderSeed : settings.seedIndex - 1
        if seedTexture == nil || shaderSeedIndex != lastSeedIndex {
            seedTexture = makeSeedTexture(index: shaderSeedIndex)
            lastSeedIndex = shaderSeedIndex
        }

        let dateSeconds = Float(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86400.0))
        for _ in 0..<steps {
            var uniforms = SimUniforms(frame: frame, seedIndex: Int32(shaderSeedIndex), dateSeconds: dateSeconds)
            encodeStep("passA", inputs: [bufferC, seedTexture], uniforms: &uniforms, commandBuffer: commandBuffer)
            encodeStep("passB", inputs: [bufferA], uniforms: &uniforms, commandBuffer: commandBuffer)
            encodeStep("passC", inputs: [bufferB], uniforms: &uniforms, commandBuffer: commandBuffer)
            if frame < Int32.max { frame += 1 }
        }
    }

    func presentationState(now: CFTimeInterval) -> (time: Double, palette: PaletteBlend, dyeTexture: MTLTexture?, bubbleTexture: MTLTexture?) {
        lock.lock()
        defer { lock.unlock() }

        let time = now - startTime
        return (time, paletteBlendLocked(time: time), dyeTexture, bubbleMask)
    }

    private func paletteBlendLocked(time: Double) -> PaletteBlend {
        let phase: Double
        if resolvedPaletteMode == .cycle {
            let period = max(1.0, Double(settings.paletteCycleSeconds))
            let transition = 4.0
            let cycleIndex = (time / period).rounded(.down)
            let remainder = time.truncatingRemainder(dividingBy: period)
            phase = remainder < period - transition
                ? cycleIndex
                : cycleIndex + (remainder - (period - transition)) / transition
        } else {
            phase = Double(InkPalette.phase(for: resolvedPaletteMode))
        }

        let base = phase.rounded(.down)
        let from = Int(base.truncatingRemainder(dividingBy: 3))
        let to = Int((base + 1).truncatingRemainder(dividingBy: 3))
        let t = Float(smoothstep(0, 1, phase - base))
        let isCustom = resolvedPaletteMode == .custom
        return PaletteBlend(
            warmBase: isCustom ? customWarmRGB : mix(InkPalette.warm[from], InkPalette.warm[to], t),
            warmTint: mix(InkPalette.warmTint[from], InkPalette.warmTint[to], t),
            coolBase: isCustom ? customCoolRGB : mix(InkPalette.cool[from], InkPalette.cool[to], t),
            coolTint: mix(InkPalette.coolTint[from], InkPalette.coolTint[to], t)
        )
    }

    func imagePipeline(pixelFormat: MTLPixelFormat, screenID: String) -> MTLRenderPipelineState? {
        lock.lock()
        defer { lock.unlock() }

        let key = UInt(pixelFormat.rawValue)
        if let pipeline = imagePipelines[key] {
            return pipeline
        }

        buildResources()
        guard let library = self.library else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "imageVertex")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.fragmentFunction = library.makeFunction(name: "imagePass")
        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            imagePipelines[key] = pipeline
            return pipeline
        } catch {
            AppLog.renderer.error("[Screen \(screenID, privacy: .public)] Failed image pipeline imagePass: \(String(describing: error), privacy: .public)")
            hasFatalError = true
            return nil
        }
    }

    var currentFrame: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return frame
    }

    private func buildResources() {
        if library == nil {
            guard let url = resourceURL(name: "default", extension: "metallib"),
                  let lib = try? device.makeLibrary(URL: url)
            else {
                AppLog.renderer.error("Failed to load default.metallib from \(self.resourceBundle.bundleURL.path, privacy: .public)")
                hasFatalError = true
                return
            }
            self.library = lib
        }
        guard let library = self.library else { return }

        // Simulation passes render the .rgba32Float state; pass C also writes
        // the dye channel on its own for the image pass.
        let attachmentFormats: [String: [MTLPixelFormat]] = [
            "passA": [.rgba32Float],
            "passB": [.rgba32Float],
            "passC": [.rgba32Float, .r32Float],
        ]
        for (name, formats) in attachmentFormats where pipelines[name] == nil {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            descriptor.fragmentFunction = library.makeFunction(name: name)
            for (index, format) in formats.enumerated() {
                descriptor.colorAttachments[index].pixelFormat = format
            }
            do {
                pipelines[name] = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                AppLog.renderer.error("Failed offscreen pipeline \(name, privacy: .public): \(String(describing: error), privacy: .public)")
                hasFatalError = true
            }
        }

        if self.sampler == nil {
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            self.sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        }
    }

    /// Every pass covers its whole target, so nothing is cleared or loaded and
    /// the first iteration initialises all of them before the image reads dye.
    private func makeTextures() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: Self.bufferWidth,
            height: Self.bufferHeight,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        bufferA = device.makeTexture(descriptor: descriptor)
        bufferB = device.makeTexture(descriptor: descriptor)
        bufferC = device.makeTexture(descriptor: descriptor)
        descriptor.pixelFormat = .r32Float
        dyeTexture = device.makeTexture(descriptor: descriptor)

        let targets: [String: [MTLTexture?]] = [
            "passA": [bufferA],
            "passB": [bufferB],
            "passC": [bufferC, dyeTexture],
        ]
        for (name, textures) in targets {
            let passDescriptor = MTLRenderPassDescriptor()
            for (index, texture) in textures.enumerated() {
                passDescriptor.colorAttachments[index].texture = texture
                passDescriptor.colorAttachments[index].loadAction = .dontCare
                passDescriptor.colorAttachments[index].storeAction = .store
            }
            passDescriptors[name] = passDescriptor
        }
    }

    private func encodeStep(
        _ pipelineName: String,
        inputs: [MTLTexture?],
        uniforms: inout SimUniforms,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let descriptor = passDescriptors[pipelineName],
              descriptor.colorAttachments[0].texture != nil
        else {
            AppLog.renderer.error("Offscreen pass \(pipelineName, privacy: .public) missing target")
            hasFatalError = true
            return
        }
        guard let pipeline = pipelines[pipelineName] else {
            AppLog.renderer.error("Offscreen pass \(pipelineName, privacy: .public) missing pipeline")
            hasFatalError = true
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            AppLog.renderer.error("Offscreen pass \(pipelineName, privacy: .public) could not create encoder")
            hasFatalError = true
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SimUniforms>.stride, index: 0)
        for (index, texture) in inputs.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeBubbleMaskTexture() -> MTLTexture? {
        guard let url = resourceURL(name: "bubble-mask", extension: "raw"),
              let data = try? Data(contentsOf: url),
              data.count == 256 * 128
        else {
            AppLog.renderer.error("Failed to load bubble-mask.raw from \(self.resourceBundle.bundleURL.path, privacy: .public)")
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 256, height: 128, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        data.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, 256, 128), mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: 256)
        }
        return texture
    }

    private func makeSeedTexture(index: Int) -> MTLTexture? {
        if index >= 6 { return nil } // 6 is procedural
        guard let url = resourceURL(name: "seed_\(index)", extension: "raw"),
              let data = try? Data(contentsOf: url),
              data.count == 320 * 180 * 8
        else {
            AppLog.renderer.error("Failed to load seed_\(index).raw")
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 320, height: 180, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        data.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, 320, 180), mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: 320 * 8)
        }
        return texture
    }

    private func resourceURL(name: String, extension ext: String) -> URL? {
        let fileName = "\(name).\(ext)"
        let candidates = [
            resourceBundle.url(forResource: name, withExtension: ext),
            resourceBundle.resourceURL?.appendingPathComponent(fileName),
            resourceBundle.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Resources")
                .appendingPathComponent(fileName),
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.resourceURL?.appendingPathComponent(fileName),
        ]

        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private final class SplatoonSimulationPool {
    static let shared = SplatoonSimulationPool()

    private struct Entry {
        var simulation: SplatoonSimulation
        var references: Int
    }

    private var entries: [UInt64: Entry] = [:]
    private let lock = NSLock()

    func acquire(device: MTLDevice, resourceBundle: Bundle, screenID: String) -> SplatoonSimulation? {
        let key = device.registryID
        lock.lock()
        if var entry = entries[key] {
            entry.references += 1
            entries[key] = entry
            let simulation = entry.simulation
            lock.unlock()
            AppLog.renderer.debug("[Screen \(screenID, privacy: .public)] Reusing shared simulation, device=\(key), references=\(entry.references)")
            return simulation
        }
        lock.unlock()

        guard let simulation = SplatoonSimulation(device: device, resourceBundle: resourceBundle, screenID: screenID) else {
            return nil
        }

        lock.lock()
        if var entry = entries[key] {
            entry.references += 1
            entries[key] = entry
            let existing = entry.simulation
            lock.unlock()
            return existing
        }
        entries[key] = Entry(simulation: simulation, references: 1)
        lock.unlock()
        return simulation
    }

    func release(_ simulation: SplatoonSimulation) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[simulation.key] else { return }
        entry.references -= 1
        if entry.references <= 0 {
            entries.removeValue(forKey: simulation.key)
        } else {
            entries[simulation.key] = entry
        }
    }
}

final class SplatoonRenderer: NSObject {
    private let simulation: SplatoonSimulation
    private weak var metalLayer: CAMetalLayer?
    private var imagePipeline: MTLRenderPipelineState?
    private var imagePipelinePixelFormat: MTLPixelFormat?
    private var loggedInitialFrames = 0
    private(set) var hasFatalError = false
    private let screenID: String

    // nextDrawable() blocks for up to a second once the layer stops being
    // displayed, which is how System Settings tears down its remotely hosted
    // preview. Fetching drawables here keeps that wait off the host's main
    // thread, which must stay free to process the teardown and set up the
    // replacement preview.
    private let drawableQueue = DispatchQueue(label: "ink.space4.Splatoon3Screensaver.drawable", qos: .userInteractive)
    private let drawableLock = NSLock()
    private var readyDrawable: CAMetalDrawable?
    private var isFetchingDrawable = false

    init?(
        layer: CAMetalLayer,
        device: MTLDevice,
        resourceBundle: Bundle,
        screenID: String
    ) {
        guard let simulation = SplatoonSimulationPool.shared.acquire(
            device: device,
            resourceBundle: resourceBundle,
            screenID: screenID
        ) else {
            return nil
        }
        self.simulation = simulation
        self.metalLayer = layer
        self.screenID = screenID
        super.init()
        self.hasFatalError = simulation.hasFatalError
        AppLog.renderer.debug("[Screen \(self.screenID, privacy: .public)] Renderer initialized, sharedDevice=\(simulation.key), resourceBundle=\(resourceBundle.bundleURL.path, privacy: .public)")
    }

    deinit {
        SplatoonSimulationPool.shared.release(simulation)
    }

    func reloadSettings(forceReset: Bool = false) {
        simulation.reloadSettings(forceReset: forceReset)
        hasFatalError = simulation.hasFatalError
    }

    func handleResize(to size: CGSize) {
        // Simulation buffers are shared and fixed-size. The per-screen drawable size
        // is applied only to the final image pass.
    }

    func draw() {
        if hasFatalError || simulation.hasFatalError { return }
        guard let metalLayer = self.metalLayer,
              let drawable = takeReadyDrawable(),
              let commandBuffer = simulation.makeCommandBuffer()
        else {
            #if DEBUG
            AppLog.renderer.debug("[Screen \(self.screenID, privacy: .public)] Draw skipped; layerExists=\(self.metalLayer != nil)")
            #endif
            return
        }

        let now = CACurrentMediaTime()
        simulation.advance(commandBuffer: commandBuffer, now: now)
        let state = simulation.presentationState(now: now)
        // The drawable may predate a resize, so size the image from its texture.
        let drawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        var uniforms = makeImageUniforms(time: state.time, drawableSize: drawableSize, palette: state.palette)

        if loggedInitialFrames < 3 {
            AppLog.renderer.debug("[Screen \(self.screenID, privacy: .public)] Drawing frame=\(self.simulation.currentFrame), drawable=\(drawableSize.debugDescription, privacy: .public), sharedBuffer=640x360")
            loggedInitialFrames += 1
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store

        guard let imagePipeline = cachedImagePipeline(for: metalLayer.pixelFormat) else {
            AppLog.renderer.error("[Screen \(self.screenID, privacy: .public)] Missing image pipeline imagePass")
            hasFatalError = true
            commandBuffer.commit()
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            AppLog.renderer.error("[Screen \(self.screenID, privacy: .public)] Could not create drawable encoder")
            hasFatalError = true
            commandBuffer.commit()
            return
        }
        encoder.setRenderPipelineState(imagePipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ImageUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ImageUniforms>.stride, index: 0)
        encoder.setFragmentTexture(state.dyeTexture, index: 0)
        encoder.setFragmentTexture(state.bubbleTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        // Plain present only: present(afterMinimumDuration:) waits for the previous
        // drawable to be displayed, which never happens once the host stops
        // displaying the layer.
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// The drawable fetched since the last frame, or nil if it is not ready, in
    /// which case this frame is skipped instead of waiting.
    private func takeReadyDrawable() -> CAMetalDrawable? {
        drawableLock.lock()
        let drawable = readyDrawable
        readyDrawable = nil
        drawableLock.unlock()
        fetchDrawableIfNeeded()
        return drawable
    }

    private func fetchDrawableIfNeeded() {
        drawableLock.lock()
        guard !isFetchingDrawable, readyDrawable == nil, let layer = metalLayer else {
            drawableLock.unlock()
            return
        }
        isFetchingDrawable = true
        drawableLock.unlock()

        let screenID = self.screenID
        drawableQueue.async { [weak self, weak layer] in
            let start = CACurrentMediaTime()
            let drawable = layer?.nextDrawable()
            let waited = CACurrentMediaTime() - start
            if waited > 0.25 {
                AppLog.renderer.info("[Screen \(screenID, privacy: .public)] nextDrawable waited \(waited, format: .fixed(precision: 2))s; the layer is not being displayed")
            }
            guard let self else { return }
            self.drawableLock.lock()
            self.readyDrawable = drawable
            self.isFetchingDrawable = false
            self.drawableLock.unlock()
        }
    }

    /// Bubble wobble, breathing and scroll from the original image shader,
    /// folded into two affine maps of screen uv. Evaluating them here in double
    /// precision keeps long-running animation smooth and leaves the fragment
    /// shader only texture reads and a blend.
    private func makeImageUniforms(time: Double, drawableSize: CGSize, palette: PaletteBlend) -> ImageUniforms {
        let loop = 2000.0 / 60.0
        let lp = fract(time / loop)
        let fr = lp * 2000.0

        let coolWobble = lp < 0.3265
            ? mix(0.0, 1.58748, smoothstep(0.0, 0.3265, lp))
            : mix(1.58748, 0.0, smoothstep(0.3265, 1.0, lp))
        let warmWobble: Double
        if lp < 0.2695 {
            warmWobble = mix(0.0, -9.0, smoothstep(0.0, 0.2695, lp))
        } else if lp < 0.6435 {
            warmWobble = mix(-9.0, 12.0, smoothstep(0.2695, 0.6435, lp))
        } else {
            warmWobble = mix(12.0, 0.0, smoothstep(0.6435, 1.0, lp))
        }

        func breath(_ frame: Double, period: Double, peak: Double, scale: Double) -> Double {
            let lf = frame.truncatingRemainder(dividingBy: period)
            let s = lf < peak ? smoothstep(0.0, peak, lf) : 1.0 - smoothstep(peak, period, lf)
            return mix(1.0, scale, s)
        }
        let coolScale = 4.48 * breath(fr, period: 400.0, peak: 226.0, scale: 2.30 / 2.24722)
        let warmScaleX = 3.5 * breath(fr, period: 500.0, peak: 118.0, scale: 0.52037 / 0.5)
        let warmScaleY = 3.5 * breath(fr, period: 500.0, peak: 351.0, scale: 0.52037 / 0.5)

        // Columns of the shader's rot(): (cos, -sin) and (sin, cos).
        func rotation(degrees: Double) -> (SIMD2<Double>, SIMD2<Double>) {
            let a = degrees * .pi / 180.0
            return (SIMD2(cos(a), -sin(a)), SIMD2(sin(a), cos(a)))
        }
        let (coolCol0, coolCol1) = rotation(degrees: coolWobble)
        let (warmCol0, warmCol1) = rotation(degrees: warmWobble)

        // Shader: buv = (uv.x, uv.y * yf), cen = (0.5, 0.5 * yf),
        // cool = (R (buv - cen) + cen) * coolScale - scroll * (1, 1) * time,
        // warm = R ((buv - cen) * warmScale) + cen + scroll * (1, -1) * time.
        let width = max(Double(drawableSize.width), 1)
        let yf = 2.0 * Double(drawableSize.height) / width
        let center = SIMD2(0.5, 0.5 * yf)
        let scroll = time / loop

        let coolA = coolCol0 * coolScale
        let coolB = coolCol1 * (coolScale * yf)
        let coolOffset = (center - 0.5 * coolCol0 - (0.5 * yf) * coolCol1) * coolScale - SIMD2(scroll, scroll)
        let warmA = warmCol0 * warmScaleX
        let warmB = warmCol1 * (warmScaleY * yf)
        let warmOffset = center - 0.5 * warmA - 0.5 * warmB + SIMD2(scroll, -scroll)

        // The bubble sampler repeats, so whole-texture offsets can be dropped.
        func wrapped(_ v: SIMD2<Double>) -> SIMD2<Float> {
            SIMD2(Float(fract(v.x)), Float(fract(v.y)))
        }
        func floats(_ v: SIMD2<Double>) -> SIMD2<Float> {
            SIMD2(Float(v.x), Float(v.y))
        }

        return ImageUniforms(
            coolTransform: SIMD4(lowHalf: floats(coolA), highHalf: floats(coolB)),
            warmTransform: SIMD4(lowHalf: floats(warmA), highHalf: floats(warmB)),
            bubbleOffset: SIMD4(lowHalf: wrapped(coolOffset), highHalf: wrapped(warmOffset)),
            warmBase: SIMD4(palette.warmBase, 0),
            warmTint: SIMD4(palette.warmTint, 0),
            coolBase: SIMD4(palette.coolBase, 0),
            coolTint: SIMD4(palette.coolTint, 0)
        )
    }

    private func cachedImagePipeline(for pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        if imagePipelinePixelFormat == pixelFormat, let imagePipeline {
            return imagePipeline
        }

        guard let pipeline = simulation.imagePipeline(pixelFormat: pixelFormat, screenID: screenID) else {
            return nil
        }
        imagePipeline = pipeline
        imagePipelinePixelFormat = pixelFormat
        return pipeline
    }
}
