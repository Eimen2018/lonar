import CoreGraphics
import Foundation

/// Maps built-in brightness (0–1) through a per-display curve to a DDC value
/// and writes it out — coalesced, stepped, and rate-limited so the steady
/// state produces zero I2C traffic and ramps never flood the monitor.
final class SyncEngine: ObservableObject {
    enum DisplayState: Equatable {
        case idle
        case syncing
        case ddcFailed
    }

    @Published private(set) var displayStates: [CGDirectDisplayID: DisplayState] = [:]
    @Published private(set) var lastTargets: [CGDirectDisplayID: Int] = [:]

    private let settings: AppSettings
    private var workers: [CGDirectDisplayID: DisplayWorker] = [:]
    private var lastBuiltin: Float?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func displaysChanged(_ displays: [ExternalDisplay]) {
        for worker in workers.values { worker.cancel() }
        workers = displays.reduce(into: [:]) { dict, display in
            let worker = DisplayWorker(display: display) { [weak self] state in
                DispatchQueue.main.async {
                    self?.displayStates[display.id] = state
                }
            }
            // Seed from the monitor's actual value so the first ramp starts
            // from reality instead of jumping.
            if let initial = display.initialValue {
                worker.seed(lastWritten: Int(initial))
            }
            dict[display.id] = worker
        }
        displayStates = displays.reduce(into: [:]) { $0[$1.id] = .idle }
        // Bring the new topology in line with the current built-in level.
        if let value = lastBuiltin { builtinChanged(value) }
    }

    func builtinChanged(_ value: Float) {
        lastBuiltin = value
        guard settings.syncEnabled else { return }
        for (id, worker) in workers {
            let curve = settings.curve(for: worker.display.edidUUID)
            let target = Self.mapBrightness(
                builtin: value, curve: curve, maxValue: Int(worker.display.maxBrightness)
            )
            lastTargets[id] = target
            worker.setTarget(target)
        }
    }

    /// Re-apply the current built-in level (used when sync is re-enabled or
    /// curve settings change).
    func resync() {
        if let value = lastBuiltin { builtinChanged(value) }
    }

    /// Manual slider: write through the same stepped path. Auto-sync resumes
    /// on the next built-in brightness change.
    func setManual(displayID: CGDirectDisplayID, percent: Double) {
        guard let worker = workers[displayID] else { return }
        let target = Int((percent / 100.0 * Double(worker.display.maxBrightness)).rounded())
        lastTargets[displayID] = target
        worker.setTarget(target)
    }

    static func mapBrightness(builtin: Float, curve: DisplayCurve, maxValue: Int) -> Int {
        let clamped = Double(min(max(builtin, 0), 1))
        let shaped = pow(clamped, curve.gamma)
        let pct = curve.minPercent + (curve.maxPercent - curve.minPercent) * shaped
        return Int((pct / 100.0 * Double(maxValue)).rounded())
    }
}

/// One per external display. All DDC writes for a display happen on its own
/// serial queue: max one step per `writeInterval`, max `maxStep` units per
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
        guard let target = pending else { finish() ; return }
        if let written = lastWritten, written == target { finish(); return }

        let next: Int
        if let written = lastWritten {
            let delta = max(-maxStep, min(maxStep, target - written))
            next = written + delta
        } else {
            next = target
        }

        let ok = AppleSiliconDDC.write(
            service: display.service, command: VCP.brightness, value: UInt16(max(0, next))
        )
        if ok {
            consecutiveFailures = 0
            lastWritten = next
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= failureLimit {
                running = false
                onState(.ddcFailed)
                // Reprobe later: keep the pending target and try again.
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

    private func finish() {
        running = false
        onState(.idle)
    }
}
