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
    private static var idleExitWorkItem: DispatchWorkItem?

    private var metalLayer: CAMetalLayer?
    private var renderer: SplatoonRenderer?
    private var configController: ConfigSheetController?
    private var isRendering = false
    private var animationActive = false
    private var activeAnimationInterval: TimeInterval = 1.0 / 60.0
    private let inactiveAnimationInterval: TimeInterval = 10.0

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
        } else if window == nil {
            suspendRendering(reason: "view removed from window")
            scheduleIdleExit()
        }
    }

    private func setupRenderer() {
        guard let metalLayer = self.metalLayer else { return }
        
        let screen = window?.screen ?? NSScreen.main
        guard let device = screen?.metalDevice ?? MTLCreateSystemDefaultDevice() else {
            AppLog.renderer.error("No Metal device is available for this screen.")
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
            resourceBundle: Bundle(for: type(of: self))
        )
        
        if renderer == nil {
            AppLog.renderer.error("Failed to initialize SplatoonRenderer.")
            return
        }
        
        if renderer?.hasFatalError == true {
            AppLog.renderer.error("Fatal error during renderer initialization (missing resources or pipeline compilation failure).")
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
        cancelIdleExit()
        animationActive = true
        if renderer == nil {
            setupRenderer()
        }
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
        AppLog.renderer.info("Animation started, isPreview=\(self.isPreview), interval=\(self.animationTimeInterval)")
    }

    public override func stopAnimation() {
        suspendRendering(reason: "stopAnimation")
        scheduleIdleExit()
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
        return !isPreview || isPreviewHostVisibleToUser
    }

    private func updateAnimationInterval(canRender: Bool) {
        if canRender {
            cancelIdleExit()
        } else {
            scheduleIdleExit()
        }

        let targetInterval = canRender ? activeAnimationInterval : inactiveAnimationInterval
        if abs(animationTimeInterval - targetInterval) > .ulpOfOne {
            animationTimeInterval = targetInterval
        }
    }

    private var isPreviewHostVisibleToUser: Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        if frontmostApp.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }

        return frontmostApp.bundleIdentifier == "com.apple.systempreferences"
            || frontmostApp.localizedName == "System Settings"
            || frontmostApp.localizedName == "系统设置"
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
        scheduleIdleExit()
    }

    @objc private func screenSaverDidStop() {
        stopAnimation()
    }

    @objc private func workspaceApplicationVisibilityChanged() {
        guard isPreview else { return }
        let canRender = shouldRenderFrame
        updateAnimationInterval(canRender: canRender)
        if canRender {
            renderFrame()
        }
    }

    private func suspendRendering(reason: StaticString) {
        animationActive = false
        animationTimeInterval = inactiveAnimationInterval
        renderer = nil
        isRendering = false
        AppLog.renderer.info("Rendering suspended: \(reason)")
    }

    private func cancelIdleExit() {
        Self.idleExitWorkItem?.cancel()
        Self.idleExitWorkItem = nil
    }

    private func scheduleIdleExit() {
        guard Self.idleExitWorkItem == nil else { return }
        let workItem = DispatchWorkItem {
            AppLog.renderer.info("Idle screen saver host exiting")
            exit(0)
        }
        Self.idleExitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 65.0, execute: workItem)
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
