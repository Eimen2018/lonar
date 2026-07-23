import AppKit
import CoreGraphics
import Foundation
import LonarObjC

struct ExternalDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let edidUUID: String
    let service: IOAVService
    /// Max DDC brightness value reported by the monitor (assume 100 if the read fails).
    let maxBrightness: UInt16
    /// Brightness value at discovery time, if the monitor answered the read.
    let initialValue: UInt16?
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

        let matches = AppleSiliconDDC.getServiceMatches(displayIDs: Array(externalIDs))
        return matches.compactMap { match in
            guard let service = match.service, !match.dummy else { return nil }
            let reading = AppleSiliconDDC.read(service: service, command: VCP.brightness)
            let name = match.serviceDetails.productName.isEmpty
                ? "Display \(match.displayID)" : match.serviceDetails.productName
            return ExternalDisplay(
                id: match.displayID,
                name: name,
                edidUUID: match.serviceDetails.edidUUID,
                service: service,
                maxBrightness: (reading?.max ?? 0) > 0 ? reading!.max : 100,
                initialValue: reading?.current
            )
        }
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
}
