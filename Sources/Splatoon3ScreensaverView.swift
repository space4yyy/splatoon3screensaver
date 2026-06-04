import AppKit
import MetalKit
import ScreenSaver

@objc(Splatoon3ScreensaverView)
public final class Splatoon3ScreensaverView: ScreenSaverView {
    private var metalView: MTKView?
    private var renderer: SplatoonRenderer?
    private var configController: ConfigSheetController?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupMetal()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let view = MTKView(frame: bounds, device: device)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        addSubview(view)
        metalView = view
        renderer = SplatoonRenderer(view: view, waitForFrameCompletion: true)
    }

    public override func startAnimation() {
        super.startAnimation()
        renderer?.reloadSettings(resetSimulation: false)
        metalView?.isPaused = false
    }

    public override func stopAnimation() {
        metalView?.isPaused = true
        super.stopAnimation()
    }

    public override func animateOneFrame() {
        // No-op. MTKView automatically renders using its own CVDisplayLink thread when isPaused = false.
    }

    public override var hasConfigureSheet: Bool { true }

    public override var configureSheet: NSWindow? {
        if configController == nil {
            configController = ConfigSheetController()
        }
        configController?.onChange = { [weak self] in
            self?.renderer?.reloadSettings(resetSimulation: true)
        }
        return configController?.window
    }
}

