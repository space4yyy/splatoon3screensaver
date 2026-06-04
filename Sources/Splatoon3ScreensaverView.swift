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
        self.wantsLayer = true // Force layer-backing on the parent view for correct compositing across multiple displays
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let view = MTKView(frame: bounds, device: device)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = true // Let ScreenSaverView's animateOneFrame drive rendering
        addSubview(view)
        metalView = view
        renderer = SplatoonRenderer(view: view, waitForFrameCompletion: true)
    }

    public override func startAnimation() {
        super.startAnimation()
        renderer?.reloadSettings(resetSimulation: false)
        let fps = ScreensaverSettings.load().fpsCap
        if fps > 0 {
            self.animationTimeInterval = 1.0 / Double(fps)
        } else {
            self.animationTimeInterval = 1.0 / 60.0 // Default to 60fps for sync
        }
    }

    public override func stopAnimation() {
        super.stopAnimation()
    }

    public override func animateOneFrame() {
        metalView?.draw()
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

