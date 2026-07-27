import AppKit
import CoreGraphics
import Foundation
import LonarObjC

struct ExternalDisplay: Identifiable {
    /// How this display's brightness is set.
    enum Control {
        /// Standard monitors: DDC/CI over I2C.
        case ddc(IOAVService)
        /// Apple-protocol displays (Studio Display, UltraFine, Pro Display
        /// XDR): DisplayServices, same as the built-in panel.
        case appleNative
    }

    let id: CGDirectDisplayID
    let name: String
    /// Stable settings key: EDID UUID for DDC displays, display UUID otherwise.
    let edidUUID: String
    let control: Control
    /// Max brightness value (DDC-reported; 100 for Apple-native).
    let maxBrightness: UInt16
    /// Brightness value at discovery time, if readable.
    let initialValue: UInt16?
    /// Speaker volume at discovery (DDC only; nil if the monitor won't say).
    let volume: (current: UInt16, max: UInt16)?
    /// True if the monitor reported audio muted at discovery (VCP 0x8D == 1).
    let mutedAtDiscovery: Bool?
    /// Active input source code at discovery (DDC only, VCP 0x60).
    let currentInput: UInt16?

    var supportsDDCExtras: Bool {
        if case .ddc = control { return true }
        return false
    }

    var controlLabel: String {
        switch control {
        case .ddc: return "DDC"
        case .appleNative: return "Apple"
        }
    }
}

/// Discovers external displays and pairs each with its DDC-capable IOAVService
/// using the vendored AppleSiliconDDC matching (EDID UUID + heuristics).
/// Rescans on display reconfiguration and system wake.
final class DisplayManager: ObservableObject {
    @Published private(set) var externals: [ExternalDisplay] = []

    var onDisplaysChanged: (([ExternalDisplay]) -> Void)?
    private var rescanWork: DispatchWorkItem?

    static func scan() -> [ExternalDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
        let externalIDs = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
        guard !externalIDs.isEmpty else { return [] }

        var found: [ExternalDisplay] = []
        var claimed: Set<CGDirectDisplayID> = []

        let matches = AppleSiliconDDC.getServiceMatches(displayIDs: Array(externalIDs))
        for match in matches {
            guard let service = match.service, !match.dummy else { continue }
            let reading = AppleSiliconDDC.read(service: service, command: VCP.brightness)
            let name = match.serviceDetails.productName.isEmpty
                ? (displayName(for: match.displayID) ?? "Display \(match.displayID)")
                : match.serviceDetails.productName
            claimed.insert(match.displayID)
            let volume = AppleSiliconDDC.read(service: service, command: VCP.volume)
            let input = AppleSiliconDDC.read(service: service, command: VCP.inputSelect)
            let mute = AppleSiliconDDC.read(service: service, command: VCP.audioMute)
            found.append(ExternalDisplay(
                id: match.displayID,
                name: name,
                edidUUID: match.serviceDetails.edidUUID,
                control: .ddc(service),
                maxBrightness: (reading?.max ?? 0) > 0 ? reading!.max : 100,
                initialValue: reading?.current,
                volume: volume.map { (current: $0.current, max: $0.max > 0 ? $0.max : 100) },
                mutedAtDiscovery: mute.map { $0.current == 1 },
                currentInput: input.map { $0.current & 0xFF }
            ))
        }

        // Displays with no DDC port but native brightness control are
        // Apple-protocol (Studio Display, UltraFine, Pro Display XDR).
        for id in externalIDs where !claimed.contains(id) {
            guard DisplayServices.canChangeBrightness(id) else { continue }
            let current = DisplayServices.brightness(for: id)
            found.append(ExternalDisplay(
                id: id,
                name: displayName(for: id) ?? "Apple Display",
                edidUUID: displayUUID(for: id),
                control: .appleNative,
                maxBrightness: 100,
                initialValue: current.map { UInt16(($0 * 100).rounded()) },
                volume: nil,
                mutedAtDiscovery: nil,
                currentInput: nil
            ))
        }
        return found
    }

    static func displayName(for id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }?.localizedName
    }

    static func displayUUID(for id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            return "display-\(id)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    func startObserving() {
        rescan()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(topologyChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(topologyChanged),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(topologyChanged),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
    }

    /// Debounced: AVServices can materialize a couple of seconds after hot-plug,
    /// and stale service refs must be recreated after sleep.
    @objc private func topologyChanged() {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescan() }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func rescan() {
        let found = Self.scan()
        externals = found
        onDisplaysChanged?(found)
    }
}

enum VCP {
    static let brightness: UInt8 = 0x10
    static let volume: UInt8 = 0x62
    static let inputSelect: UInt8 = 0x60
    /// MCCS audio mute: 1 = muted, 2 = unmuted.
    static let audioMute: UInt8 = 0x8D
}

/// Common MCCS input-source codes. Monitors only respond to codes for ports
/// they physically have; the picker offers the standard set.
enum InputSource: UInt16, CaseIterable, Identifiable {
    case displayPort1 = 15
    case displayPort2 = 16
    case hdmi1 = 17
    case hdmi2 = 18
    case usbC = 27

    var id: UInt16 { rawValue }
    var label: String {
        switch self {
        case .displayPort1: return "DisplayPort 1"
        case .displayPort2: return "DisplayPort 2"
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .usbC: return "USB-C"
        }
    }
}
