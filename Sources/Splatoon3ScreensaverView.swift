import AppKit
import Metal
import QuartzCore
import ScreenSaver

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
    
    var metalDevice: MTLDevice? {
        guard let displayID = self.displayID else { return nil }
        return CGDirectDisplayCopyCurrentMetalDevice(displayID)
    }
}

@objc(Splatoon3ScreensaverView)
public final class Splatoon3ScreensaverView: ScreenSaverView {
    private var metalLayer: CAMetalLayer?
    private var renderer: SplatoonRenderer?
    private var configController: ConfigSheetController?
    private var isRendering = false
    private var activeAnimationInterval: TimeInterval = 1.0 / 60.0
    private let inactivePreviewAnimationInterval: TimeInterval = 1.0
    private var didTrySetupRenderer = false

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        self.wantsLayer = true
    }

    public override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        self.metalLayer = layer
        return layer
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && renderer == nil {
            setupRenderer()
        }
    }

    private func setupRenderer() {
        didTrySetupRenderer = true
        guard let metalLayer = self.metalLayer else { return }
        
        let screen = window?.screen ?? NSScreen.main
        guard let device = screen?.metalDevice ?? MTLCreateSystemDefaultDevice() else {
            AppLog.renderer.fault("No Metal device is available for this screen. Terminating screensaver process.")
            exit(0)
        }
        metalLayer.device = device
        
        // Ensure scale is correct initially
        let scale = window?.backingScaleFactor ?? 1.0
        metalLayer.contentsScale = scale
        
        let size = bounds.size
        let drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        metalLayer.drawableSize = drawableSize
        
        renderer = SplatoonRenderer(
            layer: metalLayer,
            device: device,
            resourceBundle: Bundle(for: type(of: self))
        )
        
        if renderer == nil {
            AppLog.renderer.fault("Failed to initialize SplatoonRenderer. Terminating screensaver process.")
            exit(0)
        }
        
        if renderer?.hasFatalError == true {
            AppLog.renderer.fault("Fatal error during renderer initialization (missing resources or pipeline compilation failure). Terminating screensaver process.")
            exit(0)
        }
        
        renderer?.handleResize(to: drawableSize)
    }

    public override func layout() {
        super.layout()
        updateLayerSize()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerSize()
    }

    private func updateLayerSize() {
        guard let metalLayer = self.metalLayer else { return }
        let scale = window?.backingScaleFactor ?? 1.0
        metalLayer.contentsScale = scale
        let size = bounds.size
        let newDrawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        if metalLayer.drawableSize != newDrawableSize {
            metalLayer.drawableSize = newDrawableSize
            renderer?.handleResize(to: newDrawableSize)
        }
    }

    public override func startAnimation() {
        super.startAnimation()
        renderer?.reloadSettings(resetSimulation: false)
        let fps = ScreensaverSettings.load().fpsCap
        if fps > 0 {
            activeAnimationInterval = 1.0 / Double(fps)
        } else {
            // Display sync mode: request up to 240fps on the timer, allowing CAMetalLayer
            // nextDrawable() to block and sync cleanly to the monitor's physical VSync.
            activeAnimationInterval = 1.0 / 240.0
        }
        self.animationTimeInterval = activeAnimationInterval
    }

    public override func stopAnimation() {
        super.stopAnimation()
    }

    public override func animateOneFrame() {
        renderFrame()
    }

    private func renderFrame() {
        updateAnimationIntervalForCurrentVisibility()
        if window != nil && didTrySetupRenderer {
            if renderer == nil || renderer?.hasFatalError == true {
                AppLog.renderer.fault("Renderer failed to initialize or has fatal error. Terminating process.")
                exit(0)
            }
        }
        guard shouldRenderFrame else { return }
        guard !isRendering else { return }
        isRendering = true
        autoreleasepool {
            renderer?.draw()
        }
        isRendering = false
    }

    private var shouldRenderFrame: Bool {
        guard let window else { return false }
        guard window.isVisible && !bounds.isEmpty else { return false }
        return !isPreview || isSystemSettingsFrontmost
    }

    private func updateAnimationIntervalForCurrentVisibility() {
        let targetInterval = shouldRenderFrame ? activeAnimationInterval : inactivePreviewAnimationInterval
        if abs(animationTimeInterval - targetInterval) > .ulpOfOne {
            animationTimeInterval = targetInterval
        }
    }

    private var isSystemSettingsFrontmost: Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        if frontmostApp.bundleIdentifier == "com.apple.systempreferences" {
            return true
        }

        return frontmostApp.localizedName == "System Settings"
            || frontmostApp.localizedName == "系统设置"
    }

    public override var hasConfigureSheet: Bool { true }

    public override var configureSheet: NSWindow? {
        if configController?.window == nil {
            configController = ConfigSheetController()
        }
        configController?.load()
        configController?.onChange = { [weak self] in
            self?.renderer?.reloadSettings(resetSimulation: true)
        }
        return configController?.window
    }
}
