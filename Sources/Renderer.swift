import Foundation
import Metal
import MetalKit

private struct ShaderUniforms {
    var resolution: SIMD4<Float>
    var bufferResolution: SIMD4<Float>
    var mouse: SIMD4<Float>
    var customWarm: SIMD4<Float>
    var customCool: SIMD4<Float>
    var state: SIMD4<Int32>
}

enum DebugLog {
    static let url = URL(fileURLWithPath: "/tmp/Splatoon3Screensaver.log")

    static func reset() {
        try? "Splatoon3Screensaver log\n".write(to: url, atomically: true, encoding: .utf8)
    }

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

final class SplatoonRenderer: NSObject, MTKViewDelegate {
    enum SettingsSource {
        case screenSaverDefaults
        case fixed(ScreensaverSettings)
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private weak var view: MTKView?
    private let settingsSource: SettingsSource
    private let waitForFrameCompletion: Bool

    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var sampler: MTLSamplerState!
    private var bufferA: MTLTexture?
    private var bufferB: MTLTexture?
    private var bufferCRead: MTLTexture?
    private var bufferCWrite: MTLTexture?
    private var bufferDRead: MTLTexture?
    private var bufferDWrite: MTLTexture?
    private var bubbleMask: MTLTexture?

    private var settings: ScreensaverSettings
    private var startTime = CACurrentMediaTime()
    private var lastTime = CACurrentMediaTime()
    private var frame: Int32 = 0
    private var lastDrawableSize: CGSize = .zero
    private var loggedDrawFrames = 0
    private var resolvedPaletteMode: Int = 0

    init?(
        view: MTKView,
        settingsSource: SettingsSource = .screenSaverDefaults,
        waitForFrameCompletion: Bool = false
    ) {
        guard let queue = view.device?.makeCommandQueue() else { return nil }
        self.device = view.device!
        self.queue = queue
        self.view = view
        self.settingsSource = settingsSource
        self.waitForFrameCompletion = waitForFrameCompletion
        switch settingsSource {
        case .screenSaverDefaults:
            self.settings = ScreensaverSettings.load()
        case .fixed(let settings):
            self.settings = settings
        }
        super.init()
        DebugLog.reset()
        DebugLog.write("renderer init waitForFrameCompletion=\(waitForFrameCompletion)")
        view.delegate = self
        buildResources()
        bubbleMask = makeBubbleMaskTexture()
        DebugLog.write("bubbleMaskLoaded=\(bubbleMask != nil)")
        reloadSettings(resetSimulation: true)
    }

    func reloadSettings(resetSimulation: Bool) {
        switch settingsSource {
        case .screenSaverDefaults:
            settings = ScreensaverSettings.load()
        case .fixed(let fixed):
            settings = fixed
        }
        if settings.fpsCap == 0 {
            view?.preferredFramesPerSecond = 0
        } else {
            view?.preferredFramesPerSecond = settings.fpsCap
        }
        if resetSimulation {
            frame = 0
            loggedDrawFrames = 0
            startTime = CACurrentMediaTime()
            lastTime = startTime
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
        DebugLog.write("reloadSettings reset=\(resetSimulation) fps=\(settings.fpsCap) scale=\(settings.renderScale) palette=\(settings.paletteMode) resolvedPalette=\(resolvedPaletteMode)")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lastDrawableSize = size
        recreateTextures()
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer()
        else {
            if loggedDrawFrames < 20 {
                DebugLog.write("draw skipped drawable=\(view.currentDrawable != nil) descriptor=\(view.currentRenderPassDescriptor != nil)")
                loggedDrawFrames += 1
            }
            return
        }

        if texturesNeedResize(for: view.drawableSize) {
            recreateTextures()
        }

        let now = CACurrentMediaTime()
        let time = Float(now - startTime)
        let delta = min(Float(now - lastTime), 1.0 / 15.0)
        lastTime = now

        var uniforms = ShaderUniforms(
            resolution: SIMD4(Float(bufferWidth), Float(bufferHeight), 1.0, settings.renderScale),
            bufferResolution: SIMD4(Float(bufferWidth), Float(bufferHeight), 1.0, time),
            mouse: SIMD4<Float>(0, 0, 0, 0),
            customWarm: SIMD4(settings.customWarm.float3, delta),
            customCool: SIMD4(settings.customCool.float3, Float(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86400.0))),
            state: SIMD4(frame, Int32(resolvedPaletteMode), 0, 0)
        )
        if loggedDrawFrames < 20 {
            DebugLog.write("draw frame=\(frame) drawableSize=\(view.drawableSize) bounds=\(view.bounds) buffer=\(bufferWidth)x\(bufferHeight)")
            loggedDrawFrames += 1
        }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        encodeOffscreen("passA", target: bufferA, input0: bufferCRead, uniforms: &uniforms, commandBuffer: commandBuffer)
        encodeOffscreen("passB", target: bufferB, input0: bufferA, uniforms: &uniforms, commandBuffer: commandBuffer)
        encodeOffscreen("passC", target: bufferCWrite, input0: bufferB, uniforms: &uniforms, commandBuffer: commandBuffer)
        encodeOffscreen("passD", target: bufferDWrite, input0: bufferDRead, uniforms: &uniforms, commandBuffer: commandBuffer)

        guard let imagePipeline = pipelines["imagePass"] else {
            DebugLog.write("missing image pipeline imagePass")
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            DebugLog.write("missing drawable encoder")
            return
        }
        uniforms.resolution = SIMD4(Float(view.drawableSize.width), Float(view.drawableSize.height), 1.0, settings.renderScale)
        encoder.setRenderPipelineState(imagePipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(bufferCWrite, index: 0)
        encoder.setFragmentTexture(bufferDWrite, index: 2)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
        if waitForFrameCompletion {
            commandBuffer.waitUntilCompleted()
        }
        swap(&bufferCRead, &bufferCWrite)
        swap(&bufferDRead, &bufferDWrite)
        frame += 1
    }

    private var bufferWidth: Int { Int(640.0 * CGFloat(settings.renderScale)) }
    private var bufferHeight: Int { Int(360.0 * CGFloat(settings.renderScale)) }

    private func buildResources() {
        guard let url = resourceURL(name: "default", extension: "metallib"),
              let library = try? device.makeLibrary(URL: url)
        else {
            DebugLog.write("failed to load default.metallib")
            return
        }

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
                    DebugLog.write("failed pipeline \(name): \(error)")
                }
            }
        }

        // 2. Image passes (.bgra8Unorm format)
        if pipelines["imagePass"] == nil {
            let imageDescriptor = MTLRenderPipelineDescriptor()
            imageDescriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            imageDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            imageDescriptor.fragmentFunction = library.makeFunction(name: "imagePass")
            do {
                pipelines["imagePass"] = try device.makeRenderPipelineState(descriptor: imageDescriptor)
            } catch {
                DebugLog.write("failed image pipeline imagePass: \(error)")
            }
        }

        if sampler == nil {
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        }
    }

    private func texturesNeedResize(for size: CGSize) -> Bool {
        guard size != .zero else { return false }
        return bufferA?.width != bufferWidth || bufferA?.height != bufferHeight
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
        lastDrawableSize = view?.drawableSize ?? .zero
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
            DebugLog.write("offscreen \(pipelineName) missing target")
            return
        }
        guard let pipeline = pipelines[pipelineName] else {
            DebugLog.write("offscreen \(pipelineName) missing pipeline")
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
            DebugLog.write("offscreen \(pipelineName) missing encoder")
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(input0, index: 0)
        if pipelineName == "passD" {
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
            DebugLog.write("failed to load bubble-mask.raw")
            return nil
        }
        DebugLog.write("loaded bubble-mask.raw \(url.path)")

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 256, height: 128, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        data.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, 256, 128), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: 256)
        }
        return texture
    }

    private func resourceURL(name: String, extension ext: String) -> URL? {
        Bundle(for: SplatoonRenderer.self).url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.resourceURL?.appendingPathComponent("\(name).\(ext)")
    }
}
