import AppKit
import MetalKit

final class PreviewController: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var metalView: MTKView!
    private var renderer: SplatoonRenderer!
    private var debugView = 0
    private var stage: SplatoonRenderer.RenderStage = .solid

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available")
        }

        metalView = MTKView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), device: device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = 60

        window = KeyWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Splatoon 3 Shader Preview - Solid"
        window.contentView = metalView
        window.makeKeyAndOrderFront(nil)

        renderer = makeRenderer()
        (window as? KeyWindow)?.onKeyDown = { [weak self] event in
            self?.handleKey(event)
        }
    }

    private func makeRenderer() -> SplatoonRenderer {
        let settings = ScreensaverSettings.previewDefaults(debugView: debugView)
        guard let renderer = SplatoonRenderer(
            view: metalView,
            settingsSource: .fixed(settings),
            renderStage: stage,
            waitForFrameCompletion: true
        ) else {
            fatalError("Could not create renderer")
        }
        return renderer
    }

    private func handleKey(_ event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "1":
            stage = .solid
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Solid"
        case "2":
            stage = .gradient
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Gradient"
        case "3":
            stage = .bubbleResource
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Bubble Resource"
        case "4":
            stage = .bufferDConstant
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Buffer D Constant"
        case "5":
            stage = .bufferDBubbleCopy
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Buffer D Bubble Copy"
        case "6":
            stage = .bufferD
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Buffer D"
        case "7":
            stage = .bufferA
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Buffer A"
        case "8":
            stage = .bufferB
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Buffer B"
        case "9":
            stage = .bufferC
            debugView = 1
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Buffer C"
        case "0":
            stage = .shadertoy
            debugView = 0
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Final"
        case "-":
            stage = .shadertoy
            debugView = 2
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Full Chain Buffer D"
        case "=":
            stage = .shadertoy
            debugView = 1
            renderer = makeRenderer()
            window.title = "Splatoon 3 Shader Preview - Full Chain Dye"
        case "r", "R":
            renderer = makeRenderer()
        default:
            break
        }
    }
}

final class KeyWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Void)?

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}

let app = NSApplication.shared
let delegate = PreviewController()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
