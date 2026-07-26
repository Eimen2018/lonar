import CoreGraphics
import Foundation

/// Software dimming below the hardware minimum ("sub-zero"): scales the
/// display's gamma output ceiling while the LED backlight stays at 0%.
/// The OS resets gamma tables on display reconfiguration, so callers must
/// re-apply after rescans (SyncEngine does this via resync).
enum GammaDimmer {
    /// Last applied multiplier per display, to skip redundant sets.
    private static var applied: [CGDirectDisplayID: Float] = [:]
    private static let lock = NSLock()

    /// multiplier 1.0 = no dimming; 0.2 = darkest sub-zero step.
    static func setMultiplier(_ multiplier: Float, for displayID: CGDirectDisplayID) {
        lock.lock()
        defer { lock.unlock() }
        let clamped = min(max(multiplier, 0.2), 1.0)
        if let last = applied[displayID], abs(last - clamped) < 0.004 { return }
        applied[displayID] = clamped
        CGSetDisplayTransferByFormula(
            displayID,
            0, clamped, 1,
            0, clamped, 1,
            0, clamped, 1
        )
    }

    /// Forget cached state (after display reconfiguration resets the tables).
    static func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        applied.removeAll()
    }

    /// Restore system gamma (call on quit).
    static func restoreAll() {
        lock.lock()
        defer { lock.unlock() }
        applied.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}
