import Foundation
import Metal
import OSLog
import QuartzCore

private struct ShaderUniforms {
    var resolution: SIMD4<Float>
    var bufferResolution: SIMD4<Float>
    var mouse: SIMD4<Float>
    var customWarm: SIMD4<Float>
    var customCool: SIMD4<Float>
    var state: SIMD4<Int32>
}

enum AppLog {
    static let renderer = Logger(subsystem: ScreensaverSettings.moduleName, category: "renderer")
}

private final class SplatoonSimulation {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let resourceBundle: Bundle

    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var imagePipelines: [UInt: MTLRenderPipelineState] = [:]
    private var sampler: MTLSamplerState?
    private var library: MTLLibrary?
    private var bufferA: MTLTexture?
    private var bufferB: MTLTexture?
    private var bufferCRead: MTLTexture?
    private var bufferCWrite: MTLTexture?
    private var bufferDRead: MTLTexture?
    private var bufferDWrite: MTLTexture?
    private var bubbleMask: MTLTexture?
    private var seedTexture: MTLTexture?
    private var lastSeedIndex: Int = -1
    private var randomShaderSeed: Int = Int.random(in: 0...5)

    private var settings: ScreensaverSettings
    private var startTime = CACurrentMediaTime()
    private var lastTime = CACurrentMediaTime()
    private var lastUpdateTime = 0.0
    private var frame: Int32 = 0
    private var resolvedPaletteMode: Int = 0
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
        reloadSettings(resetSimulation: true)
    }

    func reloadSettings(resetSimulation: Bool) {
        lock.lock()
        defer { lock.unlock() }
        reloadSettingsLocked(resetSimulation: resetSimulation)
    }

    private func reloadSettingsLocked(resetSimulation: Bool) {
        settings = ScreensaverSettings.load()
        customWarmRGB = settings.customWarm.float3
        customCoolRGB = settings.customCool.float3

        if resetSimulation {
            frame = 0
            startTime = CACurrentMediaTime()
            lastTime = startTime
            lastUpdateTime = 0
            recreateTextures()
        }
        
        if settings.paletteMode == 0 {
            // Pick a random game (2 = Splatoon 1, 3 = Splatoon 2, 4 = Splatoon 3)
            // if we are resetting the simulation or if the palette mode was not yet resolved to a valid game
            if resetSimulation || resolvedPaletteMode < 2 || resolvedPaletteMode > 4 {
                resolvedPaletteMode = Int.random(in: 2...4)
            }
        } else {
            resolvedPaletteMode = settings.paletteMode
        }
        
        buildResources()
        AppLog.renderer.debug("Shared simulation settings reloaded, reset=\(resetSimulation), fps=\(self.settings.fpsCap), scale=\(self.settings.renderScale), palette=\(self.settings.paletteMode), cycleSeconds=\(self.settings.paletteCycleSeconds), resolvedPalette=\(self.resolvedPaletteMode)")
    }

    func makeCommandBuffer() -> MTLCommandBuffer? {
        queue.makeCommandBuffer()
    }

    func advanceIfNeeded(commandBuffer: MTLCommandBuffer, now: CFTimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        if hasFatalError { return }
        let latestSettings = ScreensaverSettings.load()
        if latestSettings != settings {
            reloadSettingsLocked(resetSimulation: true)
        }

        let updateInterval = settings.fpsCap > 0 ? 1.0 / Double(settings.fpsCap) : 1.0 / 120.0
        if frame > 0 && now - lastUpdateTime < updateInterval * 0.85 {
            return
        }

        let time = Float(now - startTime)
        let delta = min(Float(now - lastTime), 1.0 / 15.0)
        lastTime = now
        lastUpdateTime = now

        let shaderSeedIndex = settings.seedIndex == 0 ? randomShaderSeed : settings.seedIndex - 1

        if seedTexture == nil || shaderSeedIndex != lastSeedIndex {
            seedTexture = makeSeedTexture(index: shaderSeedIndex)
            lastSeedIndex = shaderSeedIndex
        }

        var uniforms = ShaderUniforms(
            resolution: SIMD4(Float(bufferWidth), Float(bufferHeight), 1.0, settings.renderScale),
            bufferResolution: SIMD4(Float(bufferWidth), Float(bufferHeight), 1.0, time),
            mouse: SIMD4<Float>(0, 0, 0, 0),
            customWarm: SIMD4(customWarmRGB, delta),
            customCool: SIMD4(customCoolRGB, Float(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86400.0))),
            state: SIMD4(frame, Int32(resolvedPaletteMode), Int32(settings.paletteCycleSeconds), Int32(shaderSeedIndex))
        )

        encodeOffscreen("passA", target: bufferA, input0: bufferCRead, uniforms: &uniforms, commandBuffer: commandBuffer)
        encodeOffscreen("passB", target: bufferB, input0: bufferA, uniforms: &uniforms, commandBuffer: commandBuffer)
        encodeOffscreen("passC", target: bufferCWrite, input0: bufferB, uniforms: &uniforms, commandBuffer: commandBuffer)
        encodeOffscreen("passD", target: bufferDWrite, input0: bufferDRead, uniforms: &uniforms, commandBuffer: commandBuffer)
        swap(&bufferCRead, &bufferCWrite)
        swap(&bufferDRead, &bufferDWrite)
        frame += 1
    }

    func presentationState(drawableSize: CGSize, now: CFTimeInterval) -> (uniforms: ShaderUniforms, cTexture: MTLTexture?, dTexture: MTLTexture?, bubbleTexture: MTLTexture?, sampler: MTLSamplerState?) {
        lock.lock()
        defer { lock.unlock() }

        var uniforms = makeUniforms(time: Float(now - startTime), delta: 0)
        uniforms.resolution = SIMD4(Float(drawableSize.width), Float(drawableSize.height), 1.0, settings.renderScale)
        return (uniforms, bufferCRead, bufferDRead, bubbleMask, sampler)
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

    private var bufferWidth: Int { 640 }
    private var bufferHeight: Int { 360 }

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

        // 1. Offscreen passes (.rgba32Float format)
        let offscreenNames = ["passA", "passB", "passC", "passD"]
        let neededOffscreen = offscreenNames.filter { pipelines[$0] == nil }
        if !neededOffscreen.isEmpty {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            descriptor.colorAttachments[0].pixelFormat = .rgba32Float
            for name in neededOffscreen {
                descriptor.fragmentFunction = library.makeFunction(name: name)
                do {
                    pipelines[name] = try device.makeRenderPipelineState(descriptor: descriptor)
                } catch {
                    AppLog.renderer.error("Failed offscreen pipeline \(name, privacy: .public): \(String(describing: error), privacy: .public)")
                    hasFatalError = true
                }
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

    private func recreateTextures() {
        let width = bufferWidth
        let height = bufferHeight
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        bufferA = device.makeTexture(descriptor: descriptor)
        bufferB = device.makeTexture(descriptor: descriptor)
        bufferCRead = device.makeTexture(descriptor: descriptor)
        bufferCWrite = device.makeTexture(descriptor: descriptor)
        bufferDRead = device.makeTexture(descriptor: descriptor)
        bufferDWrite = device.makeTexture(descriptor: descriptor)
        clearTextures()
    }

    private func clearTextures() {
        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        [bufferA, bufferB, bufferCRead, bufferCWrite, bufferDRead, bufferDWrite].compactMap { $0 }.forEach { texture in
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = texture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)?.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func encodeOffscreen(
        _ pipelineName: String,
        target: MTLTexture?,
        input0: MTLTexture?,
        uniforms: inout ShaderUniforms,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let target else {
            AppLog.renderer.error("Offscreen pass \(pipelineName, privacy: .public) missing target")
            hasFatalError = true
            return
        }
        guard let pipeline = pipelines[pipelineName] else {
            AppLog.renderer.error("Offscreen pass \(pipelineName, privacy: .public) missing pipeline")
            hasFatalError = true
            return
        }
        uniforms.resolution = SIMD4(Float(target.width), Float(target.height), 1.0, settings.renderScale)
        uniforms.bufferResolution = SIMD4(Float(target.width), Float(target.height), 1.0, uniforms.bufferResolution.w)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            AppLog.renderer.error("Offscreen pass \(pipelineName, privacy: .public) could not create encoder")
            hasFatalError = true
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(input0, index: 0)
        if pipelineName == "passA" {
            encoder.setFragmentTexture(seedTexture, index: 1)
        } else if pipelineName == "passD" {
            encoder.setFragmentTexture(bubbleMask, index: 1)
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

    private func makeUniforms(time: Float, delta: Float) -> ShaderUniforms {
        let shaderSeedIndex = settings.seedIndex == 0 ? randomShaderSeed : settings.seedIndex - 1
        return ShaderUniforms(
            resolution: SIMD4(Float(bufferWidth), Float(bufferHeight), 1.0, settings.renderScale),
            bufferResolution: SIMD4(Float(bufferWidth), Float(bufferHeight), 1.0, time),
            mouse: SIMD4<Float>(0, 0, 0, 0),
            customWarm: SIMD4(customWarmRGB, delta),
            customCool: SIMD4(customCoolRGB, Float(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86400.0))),
            state: SIMD4(frame, Int32(resolvedPaletteMode), Int32(settings.paletteCycleSeconds), Int32(shaderSeedIndex))
        )
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
    private var loggedInitialFrames = 0
    private(set) var hasFatalError = false
    private let screenID: String

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

    func reloadSettings(resetSimulation: Bool) {
        simulation.reloadSettings(resetSimulation: resetSimulation)
        hasFatalError = simulation.hasFatalError
    }

    func handleResize(to size: CGSize) {
        // Simulation buffers are shared and fixed-size. The per-screen drawable size
        // is applied only to the final image pass.
    }

    func draw() {
        if hasFatalError || simulation.hasFatalError { return }
        guard let metalLayer = self.metalLayer,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = simulation.makeCommandBuffer()
        else {
            #if DEBUG
            AppLog.renderer.debug("[Screen \(self.screenID, privacy: .public)] Draw skipped; layerExists=\(self.metalLayer != nil)")
            #endif
            return
        }

        let now = CACurrentMediaTime()
        simulation.advanceIfNeeded(commandBuffer: commandBuffer, now: now)
        let state = simulation.presentationState(drawableSize: metalLayer.drawableSize, now: now)
        var uniforms = state.uniforms

        if loggedInitialFrames < 3 {
            AppLog.renderer.debug("[Screen \(self.screenID, privacy: .public)] Drawing frame=\(self.simulation.currentFrame), drawable=\(metalLayer.drawableSize.debugDescription, privacy: .public), sharedBuffer=640x360")
            loggedInitialFrames += 1
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store

        guard let imagePipeline = simulation.imagePipeline(pixelFormat: metalLayer.pixelFormat, screenID: screenID) else {
            AppLog.renderer.error("[Screen \(self.screenID, privacy: .public)] Missing image pipeline imagePass")
            hasFatalError = true
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            AppLog.renderer.error("[Screen \(self.screenID, privacy: .public)] Could not create drawable encoder")
            hasFatalError = true
            return
        }
        encoder.setRenderPipelineState(imagePipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(state.cTexture, index: 0)
        encoder.setFragmentTexture(state.bubbleTexture, index: 1)
        encoder.setFragmentTexture(state.dTexture, index: 2)
        encoder.setFragmentSamplerState(state.sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
