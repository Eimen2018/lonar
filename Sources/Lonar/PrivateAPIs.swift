import CoreGraphics
import Foundation

/// Loader for the private DisplayServices framework, used to read the
/// built-in panel's brightness. Every symbol is resolved with dlsym and
/// nil-checked so a future macOS removing one degrades gracefully.
enum DisplayServices {
    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    private static func sym<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool

    private static let getBrightnessFn = sym("DisplayServicesGetBrightness", as: GetBrightnessFn.self)
    private static let setBrightnessFn = sym("DisplayServicesSetBrightness", as: SetBrightnessFn.self)
    private static let canChangeFn = sym("DisplayServicesCanChangeBrightness", as: CanChangeFn.self)

    static var isAvailable: Bool { getBrightnessFn != nil }

    static func brightness(for displayID: CGDirectDisplayID) -> Float? {
        guard let fn = getBrightnessFn else { return nil }
        var value: Float = 0
        guard fn(displayID, &value) == 0 else { return nil }
        return value
    }

    static func canChangeBrightness(_ displayID: CGDirectDisplayID) -> Bool {
        canChangeFn?(displayID) ?? false
    }

    /// Debug-only (used by the `builtin-set` CLI subcommand to exercise sync).
    @discardableResult
    static func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) -> Bool {
        guard let fn = setBrightnessFn else { return false }
        return fn(displayID, value) == 0
    }

    // Signature per Lunar's bridging header:
    //   int DisplayServicesRegisterForBrightnessChangeNotifications(
    //       CGDirectDisplayID display, CGDirectDisplayID displayObserver, CFNotificationCallback callback);
    private typealias RegisterNotifFn = @convention(c) (CGDirectDisplayID, CGDirectDisplayID, CFNotificationCallback?) -> Int32
    private typealias UnregisterNotifFn = @convention(c) (CGDirectDisplayID, CGDirectDisplayID) -> Int32

    private static let registerNotifFn = sym(
        "DisplayServicesRegisterForBrightnessChangeNotifications", as: RegisterNotifFn.self)
    private static let unregisterNotifFn = sym(
        "DisplayServicesUnregisterForBrightnessChangeNotifications", as: UnregisterNotifFn.self)

    static func registerForBrightnessChanges(
        _ displayID: CGDirectDisplayID, callback: CFNotificationCallback
    ) -> Bool {
        guard let fn = registerNotifFn else { return false }
        return fn(displayID, displayID, callback) == 0
    }

    static func unregisterForBrightnessChanges(_ displayID: CGDirectDisplayID) {
        _ = unregisterNotifFn?(displayID, displayID)
    }
}
