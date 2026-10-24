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
    private var cachedIsHostVisible: Bool = true

    private static var instanceCounter = 0
    private lazy var instanceID: Int = {
        Self.instanceCounter += 1
        return Self.instanceCounter
    }()

    // When the options sheet closes, System Settings replaces its preview: the
    // host sends startAnimation to the outgoing view, removes that view without
    // stopAnimation, and never starts the replacement, which stays black. An
    // animating view removed this way hands its animation to the replacement.
    private static let liveViews = NSHashTable<Splatoon3ScreensaverView>.weakObjects()
    private static var abandonedAnimationTime: CFTimeInterval?
    private static let handoffDelay: TimeInterval = 0.3
    private static let handoffWindow: CFTimeInterval = 3.0

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupLayer()
        observeLifecycleNotifications()
        Self.liveViews.add(self)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        observeLifecycleNotifications()
        Self.liveViews.add(self)
    }

    deinit {
        AppLog.renderer.debug("[View \(self.instanceID, privacy: .public)] View deallocated")
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
        AppLog.renderer.debug("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] \(self.window == nil ? "Removed from" : "Added to", privacy: .public) window, size=\(self.bounds.size.debugDescription, privacy: .public)")
        if window == nil {
            if animationActive {
                Self.abandonedAnimationTime = CACurrentMediaTime()
                Self.scheduleAnimationHandoff()
            }
            suspendRendering(reason: "view removed from window")
            // A detached view's timer keeps waking the host about 60 times a
            // second without drawing anything.
            if isAnimating {
                super.stopAnimation()
            }
        } else if let abandoned = Self.abandonedAnimationTime,
                  CACurrentMediaTime() - abandoned < Self.handoffWindow {
            Self.scheduleAnimationHandoff()
        }
    }

    /// Starts views in a window that the host left stopped shortly after an
    /// animating view was removed. The delay lets the host start them itself.
    private static func scheduleAnimationHandoff() {
        DispatchQueue.main.asyncAfter(deadline: .now() + handoffDelay) {
            guard let abandoned = abandonedAnimationTime,
                  CACurrentMediaTime() - abandoned < handoffWindow
            else { return }
            for view in liveViews.allObjects where view.window != nil && !view.animationActive && !view.bounds.isEmpty {
                abandonedAnimationTime = nil
                AppLog.renderer.info("[Screen \(view.screenID, privacy: .public)] [View \(view.instanceID, privacy: .public)] Starting replacement view the host left stopped")
                view.startAnimation()
            }
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
        metalLayer.isHidden = false
        
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
        if animationActive {
            updateHostVisibility()
            guard shouldRenderFrame else {
                pauseRendering(reason: "host not visible")
                return
            }
            animationTimeInterval = activeAnimationInterval
            if renderer == nil {
                setupRenderer()
            }
            return
        }
        animationActive = true
        updateHostVisibility()
        guard shouldRenderFrame else {
            pauseRendering(reason: "host not visible")
            return
        }
        refreshFrameInterval()
        if renderer == nil {
            setupRenderer()
        }
        self.animationTimeInterval = activeAnimationInterval
        AppLog.renderer.info("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] Animation started, isPreview=\(self.isPreview), interval=\(self.animationTimeInterval)")
    }

    /// Applies the frame rate cap, never faster than the display refreshes, and
    /// the battery saver cap. The next frame restarts the timer if it changed.
    private func refreshFrameInterval() {
        let settings = ScreensaverSettings.load()
        let displayFPS = max((window?.screen ?? NSScreen.main)?.maximumFramesPerSecond ?? 60, 1)
        var fps = settings.fpsCap > 0 ? min(settings.fpsCap, displayFPS) : displayFPS
        if settings.batterySaver && PowerMonitor.shared.prefersReducedPower {
            fps = min(fps, ScreensaverSettings.batterySaverFPS)
        }
        let interval = 1.0 / Double(fps)
        if abs(interval - activeAnimationInterval) > .ulpOfOne {
            AppLog.renderer.info("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] Frame rate set to \(fps) fps, batterySaver=\(settings.batterySaver), reducedPower=\(PowerMonitor.shared.prefersReducedPower)")
        }
        activeAnimationInterval = interval
    }

    public override func stopAnimation() {
        suspendRendering(reason: "stopAnimation")
        super.stopAnimation()
        requestHostTermination(reason: "stopAnimation")
    }

    public override func animateOneFrame() {
        renderFrame()
    }

    private func renderFrame() {
        let canRender = shouldRenderFrame
        updateAnimationInterval(canRender: canRender)
        guard canRender else { return }
        resumeAnimationTimerIfNeeded()
        if renderer == nil {
            setupRenderer()
        }
        guard let renderer = self.renderer, !renderer.hasFatalError else { return }
        guard !isRendering else { return }
        isRendering = true
        autoreleasepool {
            renderer.draw()
        }
        isRendering = false
    }

    private var shouldRenderFrame: Bool {
        guard animationActive else { return false }
        guard let window else { return false }
        guard window.isVisible && !bounds.isEmpty else { return false }
        return cachedIsHostVisible
    }

    private func updateAnimationInterval(canRender: Bool) {
        if !canRender {
            pauseRendering(reason: "host not visible")
            return
        }

        if abs(animationTimeInterval - activeAnimationInterval) > .ulpOfOne {
            animationTimeInterval = activeAnimationInterval
            restartScreenSaverTimerIfNeeded()
        }
    }

    private func restartScreenSaverTimerIfNeeded() {
        guard self.animationActive && self.isAnimating else { return }
        super.stopAnimation()
        super.startAnimation()
    }

    private func resumeAnimationTimerIfNeeded() {
        guard animationActive && !isAnimating else { return }
        animationTimeInterval = activeAnimationInterval
        super.startAnimation()
    }

    private func updateHostVisibility() {
        if isFullScreenSaverLevelWindow {
            cachedIsHostVisible = true
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            cachedIsHostVisible = true
            return
        }

        if frontmostApp.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            cachedIsHostVisible = true
            return
        }

        let bundleID = frontmostApp.bundleIdentifier ?? ""
        let name = frontmostApp.localizedName ?? ""

        if bundleID == "com.apple.loginwindow" { cachedIsHostVisible = true; return }
        if bundleID == "com.apple.windowserver" { cachedIsHostVisible = true; return }
        if bundleID == "com.apple.systempreferences" { cachedIsHostVisible = true; return }
        if bundleID == "com.apple.ScreenSaver.Engine" { cachedIsHostVisible = true; return }
        if bundleID.contains("ScreenSaver") { cachedIsHostVisible = true; return }
        if name == "System Settings" || name == "系统设置" { cachedIsHostVisible = true; return }
        if name == "ScreenSaverEngine" || name == "legacyScreenSaver" { cachedIsHostVisible = true; return }

        cachedIsHostVisible = false
    }

    private var isFullScreenSaverLevelWindow: Bool {
        guard !isPreview, let window else { return false }
        return window.level.rawValue >= NSWindow.Level.screenSaver.rawValue
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: PowerMonitor.didChangeNotification,
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

    @objc private func powerStateDidChange() {
        guard animationActive else { return }
        refreshFrameInterval()
    }

    @objc private func workspaceApplicationVisibilityChanged() {
        updateHostVisibility()
        let canRender = shouldRenderFrame
        updateAnimationInterval(canRender: canRender)
        if canRender && !isRendering {
            renderFrame()
        }
    }

    private func pauseRendering(reason: StaticString) {
        guard renderer != nil || isRendering || isAnimating else { return }
        renderer = nil
        metalLayer?.isHidden = true
        metalLayer?.device = nil
        isRendering = false
        if isAnimating {
            super.stopAnimation()
        }
        AppLog.renderer.info("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] Rendering paused: \(reason, privacy: .public)")
    }

    private func suspendRendering(reason: StaticString) {
        let shouldLog = animationActive || isRendering || renderer != nil
        animationActive = false
        renderer = nil
        metalLayer?.isHidden = true
        metalLayer?.device = nil
        isRendering = false
        guard shouldLog else { return }
        AppLog.renderer.info("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] Rendering suspended: \(reason, privacy: .public)")
    }

    private func requestHostTermination(reason: StaticString) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            guard !self.animationActive && !self.isRendering else { return }
            AppLog.renderer.info("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] Requesting legacyScreenSaver host termination: \(reason, privacy: .public)")
            NSApp.terminate(nil)
        }
    }

    public override var hasConfigureSheet: Bool { true }

    public override var configureSheet: NSWindow? {
        AppLog.renderer.info("[Screen \(self.screenID, privacy: .public)] [View \(self.instanceID, privacy: .public)] Options sheet requested")
        if configController?.window == nil {
            configController = ConfigSheetController()
        }
        configController?.load()
        configController?.onChange = { [weak self] in
            self?.renderer?.reloadSettings()
            self?.refreshFrameInterval()
        }
        return configController?.window
    }
}
