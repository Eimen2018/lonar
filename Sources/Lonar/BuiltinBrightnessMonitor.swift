import CoreGraphics
import Foundation

/// C callback for DisplayServices brightness notifications — no captures
/// allowed, so it reaches the active monitor through a static ref. Thread of
/// delivery is undocumented; always hop to main.
private let brightnessChangeCallback: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async {
        BuiltinBrightnessMonitor.active?.handleExternalChangeSignal()
    }
}

/// Watches the built-in display's brightness (which macOS drives from the
/// ambient light sensor). Push notifications from DisplayServices are the
/// primary signal (instant, zero idle wakeups); a slow, leeway-coalesced
/// watchdog poll covers notification loss. Falls back to fast polling if
/// registration fails, and pauses polling entirely when there is nothing to
/// sync.
final class BuiltinBrightnessMonitor {
    fileprivate static weak var active: BuiltinBrightnessMonitor?

    private var timer: DispatchSourceTimer?
    private var cachedDisplayID: CGDirectDisplayID?
    private var registeredDisplayID: CGDirectDisplayID?
    private var lastValue: Float = -1
    private var paused = false
    private(set) var usingNotifications = false

    /// Fallback cadence when notifications are unavailable / watchdog cadence
    /// when they work. Generous leeway lets macOS coalesce the wakeups.
    private let fallbackInterval: TimeInterval = 0.5
    private let watchdogInterval: TimeInterval = 5.0

    /// Called on the main queue whenever brightness moves more than epsilon.
    var onChange: ((Float) -> Void)?

    static func findBuiltinDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    func currentBrightness() -> Float? {
        if cachedDisplayID == nil {
            cachedDisplayID = Self.findBuiltinDisplay()
        }
        guard let id = cachedDisplayID else { return nil }
        return DisplayServices.brightness(for: id)
    }

    func start() {
        Self.active = self
        registerForNotifications()
        restartTimer()
        poll()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        unregisterNotifications()
        if Self.active === self { Self.active = nil }
    }

    /// No sync targets (no DDC display, or sync toggled off) → stop the poll
    /// timer completely. Notifications stay registered: they cost nothing
    /// while idle and keep the UI's built-in % fresh.
    func setPaused(_ newValue: Bool) {
        guard paused != newValue else { return }
        paused = newValue
        if paused {
            timer?.cancel()
            timer = nil
        } else {
            restartTimer()
            poll()
        }
    }

    /// Display topology changed (hot-plug, lid open/close) — the built-in ID
    /// can change, so re-resolve and re-register.
    func invalidateDisplayCache() {
        unregisterNotifications()
        cachedDisplayID = nil
        registerForNotifications()
        restartTimer()
    }

    fileprivate func handleExternalChangeSignal() {
        poll()
    }

    private func registerForNotifications() {
        guard let id = cachedDisplayID ?? Self.findBuiltinDisplay() else {
            usingNotifications = false
            return
        }
        cachedDisplayID = id
        usingNotifications = DisplayServices.registerForBrightnessChanges(
            id, callback: brightnessChangeCallback)
        registeredDisplayID = usingNotifications ? id : nil
    }

    private func unregisterNotifications() {
        if let id = registeredDisplayID {
            DisplayServices.unregisterForBrightnessChanges(id)
        }
        registeredDisplayID = nil
        usingNotifications = false
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        guard !paused else { return }
        let interval = usingNotifications ? watchdogInterval : fallbackInterval
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 400))
        )
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    private func poll() {
        guard let value = currentBrightness() else { return }
        if abs(value - lastValue) > 0.005 {
            lastValue = value
            onChange?(value)
        }
    }
}
