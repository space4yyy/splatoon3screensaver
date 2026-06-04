import Foundation
import Metal

struct Uniforms {
    var resolution: SIMD4<Float>
    var bufferResolution: SIMD4<Float>
    var mouse: SIMD4<Float>
    var customWarm: SIMD4<Float>
    var customCool: SIMD4<Float>
    var state: SIMD4<Int32>
}

func sample(_ data: [Float], width: Int, x: Int, y: Int) -> SIMD4<Float> {
    let i = (y * width + x) * 4
    return SIMD4(data[i], data[i + 1], data[i + 2], data[i + 3])
}

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: MetalSelfTest /path/to/default.metallib")
}

guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue()
else {
    fatalError("Metal is not available")
}

let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
let pipelineDescriptor = MTLRenderPipelineDescriptor()
pipelineDescriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
pipelineDescriptor.fragmentFunction = library.makeFunction(name: "passDConstant")
pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba32Float
let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

let width = 640
let height = 360
let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba32Float,
    width: width,
    height: height,
    mipmapped: false
)
textureDescriptor.usage = [.renderTarget, .shaderRead]
textureDescriptor.storageMode = .shared
guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
    fatalError("Could not create texture")
}

var uniforms = Uniforms(
    resolution: SIMD4(Float(width), Float(height), 1.0, 1.0),
    bufferResolution: SIMD4(Float(width), Float(height), 1.0, 0.0),
    mouse: SIMD4(0, 0, 0, 0),
    customWarm: SIMD4(0, 0, 0, 0),
    customCool: SIMD4(0, 0, 0, 0),
    state: SIMD4(0, 0, 0, 0)
)

let renderPass = MTLRenderPassDescriptor()
renderPass.colorAttachments[0].texture = texture
renderPass.colorAttachments[0].loadAction = .clear
renderPass.colorAttachments[0].storeAction = .store
renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

guard let commandBuffer = queue.makeCommandBuffer(),
      let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
else {
    fatalError("Could not create command encoder")
}

encoder.setRenderPipelineState(pipeline)
encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
encoder.endEncoding()
commandBuffer.commit()
commandBuffer.waitUntilCompleted()

var data = Array(repeating: Float(0), count: width * height * 4)
texture.getBytes(
    &data,
    bytesPerRow: width * MemoryLayout<Float>.stride * 4,
    from: MTLRegionMake2D(0, 0, width, height),
    mipmapLevel: 0
)

print("sample_0_0=\(sample(data, width: width, x: 0, y: 0))")
print("sample_255_127=\(sample(data, width: width, x: 255, y: 127))")
print("sample_300_200=\(sample(data, width: width, x: 300, y: 200))")
print("sample_0_359=\(sample(data, width: width, x: 0, y: 359))")
print("sample_255_232=\(sample(data, width: width, x: 255, y: 232))")

var nonBlack = 0
var maxR: Float = 0
for y in 0..<height {
    for x in 0..<width {
        let r = data[(y * width + x) * 4]
        if r > 0.5 { nonBlack += 1 }
        maxR = max(maxR, r)
    }
}
print("non_black_r_gt_0_5=\(nonBlack)")
print("max_r=\(maxR)")
