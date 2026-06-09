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
    private var animationActive = false
    private var activeAnimationInterval: TimeInterval = 1.0 / 60.0
    private let inactiveAnimationInterval: TimeInterval = 10.0

    private static var instanceCounter = 0
    private lazy var instanceID: Int = {
        Self.instanceCounter += 1
        return Self.instanceCounter
    }()

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupLayer()
        observeLifecycleNotifications()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        observeLifecycleNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func setupLayer() {
        self.wantsLayer = true
    }

    private var screenID: String {
        let screen = self.window?.screen ?? NSScreen.main
        guard let displayID = screen?.displayID else { return "Unknown" }
        
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "Built-in"
        }
        return String(displayID)
    }

    public override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm_srgb
        layer.framebufferOnly = true
        self.metalLayer = layer
        return layer
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            suspendRendering(reason: "view removed from window")
        }
    }

    private func setupRenderer() {
        guard let metalLayer = self.metalLayer else { return }
        
        let screen = self.window?.screen ?? NSScreen.main
        guard let device = screen?.metalDevice ?? MTLCreateSystemDefaultDevice() else {
            AppLog.renderer.error("[Screen \(self.screenID, privacy: .public)] No Metal device is available for this screen.")
            return
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
            resourceBundle: Bundle(for: type(of: self)),
            screenID: screenID
        )
        
        if renderer == nil {
            AppLog.renderer.error("[Screen \(self.screenID, privacy: .public)] Failed to initialize SplatoonRenderer.")
            return
        }
        
        if renderer?.hasFatalError == true {
            AppLog.renderer.error("[Screen \(self.screenID, privacy: .public)] Fatal error during renderer initialization (missing resources or pipeline compilation failure).")
            return
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
        if animationActive { return }
        animationActive = true
        if renderer == nil {
            setupRenderer()
        }
        let fps = ScreensaverSettings.load().fpsCap
        if fps > 0 {
            activeAnimationInterval = 1.0 / Double(fps)
        } else {
            // Display sync mode: request up to 240fps on the timer, allowing CAMetalLayer
            // nextDrawable() to block and sync cleanly to the monitor's physical VSync.
            activeAnimationInterval = 1.0 / 240.0
        }
        self.animationTimeInterval = activeAnimationInterval
        AppLog.renderer.info("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] Animation started, isPreview=\(self.isPreview), interval=\(self.animationTimeInterval)")
    }

    public override func stopAnimation() {
        suspendRendering(reason: "stopAnimation")
        super.stopAnimation()
    }

    public override func animateOneFrame() {
        renderFrame()
    }

    private func renderFrame() {
        let canRender = shouldRenderFrame
        updateAnimationInterval(canRender: canRender)
        guard canRender else { return }
        guard let renderer = self.renderer, !renderer.hasFatalError else { return }
        guard !isRendering else { return }
        isRendering = true
        autoreleasepool {
            renderer.draw()
        }
        isRendering = false
    }

    private var shouldRenderFrame: Bool {
        guard animationActive && isAnimating else { return false }
        guard let window else { return false }
        guard window.isVisible && !bounds.isEmpty else { return false }
        return isHostVisibleToUser
    }

    private func updateAnimationInterval(canRender: Bool) {
        let targetInterval = canRender ? activeAnimationInterval : inactiveAnimationInterval
        if abs(animationTimeInterval - targetInterval) > .ulpOfOne {
            animationTimeInterval = targetInterval
            
            DispatchQueue.main.async {
                if self.isAnimating {
                    super.stopAnimation()
                    super.startAnimation()
                }
            }
        }
    }

    private var isHostVisibleToUser: Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return true // Fallback to rendering if we can't determine
        }

        if frontmostApp.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }

        let bundleID = frontmostApp.bundleIdentifier ?? ""
        let name = frontmostApp.localizedName ?? ""

        if bundleID == "com.apple.loginwindow" { return true }
        if bundleID == "com.apple.windowserver" { return true }
        if bundleID == "com.apple.systempreferences" { return true }
        if bundleID.contains("ScreenSaver") { return true }
        if name == "System Settings" || name == "系统设置" { return true }

        return false
    }

    private func observeLifecycleNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceApplicationVisibilityChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        let distributedCenter = DistributedNotificationCenter.default()
        for name in [
            "com.apple.screensaver.willstop",
            "com.apple.screensaver.didstop",
            "com.apple.screenIsUnlocked"
        ] {
            distributedCenter.addObserver(
                self,
                selector: #selector(screenSaverDidStop),
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
    }

    @objc private func screensDidSleep() {
        suspendRendering(reason: "screens did sleep")
    }

    @objc private func screenSaverDidStop() {
        stopAnimation()
    }

    @objc private func workspaceApplicationVisibilityChanged() {
        let canRender = shouldRenderFrame
        updateAnimationInterval(canRender: canRender)
        if canRender && !isRendering {
            renderFrame()
        }
    }

    private func suspendRendering(reason: StaticString) {
        if !animationActive && !isRendering { return }
        animationActive = false
        animationTimeInterval = inactiveAnimationInterval
        isRendering = false
        AppLog.renderer.info("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] Rendering suspended: \(reason, privacy: .public)")
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
