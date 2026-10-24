import Foundation
import IOKit.ps

/// Tracks battery power and Low Power Mode for the battery saver frame rate.
/// If the host's sandbox hides power sources, it reports AC power.
final class PowerMonitor {
    static let shared = PowerMonitor()
    static let didChangeNotification = Notification.Name("ink.space4.Splatoon3Screensaver.powerStateDidChange")

    private(set) var isOnBatteryPower = false
    private(set) var isLowPowerModeEnabled = false
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var lowPowerModeObserver: NSObjectProtocol?

    var prefersReducedPower: Bool {
        isOnBatteryPower || isLowPowerModeEnabled
    }

    private init() {
        isOnBatteryPower = Self.readIsOnBatteryPower()
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().update()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = source
        }
        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.update()
        }
        AppLog.renderer.info("Power state: battery=\(self.isOnBatteryPower), lowPowerMode=\(self.isLowPowerModeEnabled), notifications=\(self.powerSourceRunLoopSource != nil)")
    }

    private func update() {
        let onBattery = Self.readIsOnBatteryPower()
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard onBattery != isOnBatteryPower || lowPowerMode != isLowPowerModeEnabled else { return }
        isOnBatteryPower = onBattery
        isLowPowerModeEnabled = lowPowerMode
        AppLog.renderer.info("Power state changed: battery=\(onBattery), lowPowerMode=\(lowPowerMode)")
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func readIsOnBatteryPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (source as String) == kIOPSBatteryPowerValue
    }
}
