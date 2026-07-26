import CoreGraphics
import Foundation

/// Maps built-in brightness (0–1) through a per-display curve to a target
/// percent and writes it out — coalesced, stepped, and rate-limited so the
/// steady state produces zero I2C traffic and ramps never flood the monitor.
///
/// The target domain is **percent, -50…100**: 0…100 is hardware brightness
/// (DDC or Apple-native); -50…0 keeps hardware at 0 and applies software
/// gamma dimming ("sub-zero").
final class SyncEngine: ObservableObject {
    static let minPercent = -50
    static let maxPercent = 100

    enum DisplayState: Equatable {
        case idle
        case syncing
        case ddcFailed
    }

    @Published private(set) var displayStates: [CGDirectDisplayID: DisplayState] = [:]
    /// Latest target percent (-50…100) per display.
    @Published private(set) var lastTargets: [CGDirectDisplayID: Int] = [:]

    private let settings: AppSettings
    private var workers: [CGDirectDisplayID: DisplayWorker] = [:]
    private var lastBuiltin: Float?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func displaysChanged(_ displays: [ExternalDisplay]) {
        for worker in workers.values { worker.cancel() }
        // Reconfiguration wipes OS gamma tables; resync below re-applies.
        GammaDimmer.invalidateCache()
        workers = displays.reduce(into: [:]) { dict, display in
            let worker = DisplayWorker(display: display) { [weak self] state in
                DispatchQueue.main.async {
                    self?.displayStates[display.id] = state
                }
            }
            if let initial = display.initialValue {
                let pct = Int((Double(initial) / Double(display.maxBrightness) * 100).rounded())
                worker.seed(lastWritten: pct)
            }
            dict[display.id] = worker
        }
        displayStates = displays.reduce(into: [:]) { $0[$1.id] = .idle }
        if let value = lastBuiltin { builtinChanged(value) }
    }

    func builtinChanged(_ value: Float) {
        lastBuiltin = value
        guard settings.syncEnabled else { return }
        for (id, worker) in workers {
            let curve = settings.curve(for: worker.display.edidUUID)
            let target = Self.mapBrightness(builtin: value, curve: curve)
            lastTargets[id] = target
            worker.setTarget(target)
        }
    }

    /// Re-apply the current built-in level (sync re-enabled, curve changed,
    /// or displays rescanned).
    func resync() {
        if let value = lastBuiltin { builtinChanged(value) }
    }

    /// Manual slider / scroll: write through the same stepped path.
    /// Auto-sync resumes on the next built-in brightness change.
    func setManual(displayID: CGDirectDisplayID, percent: Double) {
        guard let worker = workers[displayID] else { return }
        let target = min(max(Int(percent.rounded()), Self.minPercent), Self.maxPercent)
        lastTargets[displayID] = target
        worker.setTarget(target)
    }

    /// Relative adjustment for scroll-to-dim; applies to every display.
    func adjustAll(byPercent delta: Int) {
        for (id, worker) in workers {
            let current = lastTargets[id]
                ?? worker.display.initialValue.map {
                    Int((Double($0) / Double(worker.display.maxBrightness) * 100).rounded())
                } ?? 50
            let target = min(max(current + delta, Self.minPercent), Self.maxPercent)
            lastTargets[id] = target
            worker.setTarget(target)
        }
    }

    /// One-off DDC command (volume, input select) on the display's queue.
    func sendCommand(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) {
        workers[displayID]?.sendCommand(command, value: value)
    }

    static func mapBrightness(builtin: Float, curve: DisplayCurve) -> Int {
        let clamped = Double(min(max(builtin, 0), 1))
        let shaped = pow(clamped, curve.gamma)
        let pct = curve.minPercent + (curve.maxPercent - curve.minPercent) * shaped
        return min(max(Int(pct.rounded()), minPercent), maxPercent)
    }
}

/// One per external display. All writes for a display happen on its own
/// serial queue: max one step per `writeInterval`, max `maxStep` percent per
/// step, and only when the target actually changed.
final class DisplayWorker {
    let display: ExternalDisplay

    private let queue: DispatchQueue
    private let onState: (SyncEngine.DisplayState) -> Void
    private var pending: Int?
    private var lastWritten: Int?
    private var running = false
    private var cancelled = false
    private var consecutiveFailures = 0

    private let maxStep = 8
    private let writeInterval: TimeInterval = 0.1
    private let failureLimit = 5
    private let reprobeDelay: TimeInterval = 30

    init(display: ExternalDisplay, onState: @escaping (SyncEngine.DisplayState) -> Void) {
        self.display = display
        self.onState = onState
        self.queue = DispatchQueue(label: "com.aymen.lonar.ddc.\(display.id)")
    }

    func seed(lastWritten value: Int) {
        queue.async { self.lastWritten = value }
    }

    func setTarget(_ target: Int) {
        queue.async {
            self.pending = target
            self.pump()
        }
    }

    /// Non-brightness DDC command (volume, input), serialized on the same
    /// queue so it never interleaves with a brightness step mid-I2C.
    func sendCommand(_ command: UInt8, value: UInt16) {
        queue.async {
            guard case .ddc(let service) = self.display.control else { return }
            _ = AppleSiliconDDC.write(service: service, command: command, value: value)
        }
    }

    func cancel() {
        queue.async { self.cancelled = true }
    }

    private func pump() {
        guard !running, !cancelled else { return }
        running = true
        onState(.syncing)
        step()
    }

    private func step() {
        guard !cancelled else { running = false; return }
        guard let target = pending else { finish(); return }
        if let written = lastWritten, written == target { finish(); return }

        let next: Int
        if let written = lastWritten {
            let delta = max(-maxStep, min(maxStep, target - written))
            next = written + delta
        } else {
            next = target
        }

        let ok = apply(percent: next)
        if ok {
            consecutiveFailures = 0
            lastWritten = next
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= failureLimit {
                running = false
                onState(.ddcFailed)
                queue.asyncAfter(deadline: .now() + reprobeDelay) { [weak self] in
                    guard let self, !self.cancelled else { return }
                    self.consecutiveFailures = 0
                    self.pump()
                }
                return
            }
        }
        queue.asyncAfter(deadline: .now() + writeInterval) { [weak self] in
            self?.step()
        }
    }

    /// percent -50…100: hardware level for the 0…100 span, software gamma
    /// dimming (backlight pinned at 0) for the negative span.
    private func apply(percent: Int) -> Bool {
        let hardware = max(0, percent)
        let ok: Bool
        switch display.control {
        case .ddc(let service):
            let value = UInt16((Double(hardware) / 100.0 * Double(display.maxBrightness)).rounded())
            ok = AppleSiliconDDC.write(service: service, command: VCP.brightness, value: value)
        case .appleNative:
            ok = DisplayServices.setBrightness(Float(hardware) / 100.0, for: display.id)
        }
        // -50 → 0.2 ceiling; ≥0 → restore full range.
        let multiplier = percent >= 0 ? Float(1.0) : 1.0 + Float(percent) / 50.0 * 0.8
        GammaDimmer.setMultiplier(multiplier, for: display.id)
        return ok
    }

    private func finish() {
        running = false
        onState(.idle)
    }
}
