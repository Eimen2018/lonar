import AppKit
import Combine
import Sparkle
import SwiftUI

@main
enum Main {
    static func main() {
        if CommandLine.arguments.count > 1 {
            CLI.run(arguments: CommandLine.arguments)
        }
        LonarApp.main()
    }
}

/// Composition root: owns the model objects and wires them together.
final class AppState: ObservableObject {
    let settings: AppSettings
    let displayManager: DisplayManager
    let syncEngine: SyncEngine
    let builtinMonitor: BuiltinBrightnessMonitor
    /// nil when running outside a .app bundle (swift run / CLI dev builds),
    /// where Sparkle has no bundle identity to update.
    let updaterController: SPUStandardUpdaterController?

    @Published var builtinBrightness: Float = 0

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.displayManager = DisplayManager()
        self.syncEngine = SyncEngine(settings: settings)
        self.builtinMonitor = BuiltinBrightnessMonitor()
        self.updaterController = Bundle.main.bundlePath.hasSuffix(".app")
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil

        displayManager.onDisplaysChanged = { [weak self] displays in
            self?.builtinMonitor.invalidateDisplayCache()
            self?.syncEngine.displaysChanged(displays)
            self?.updatePauseState()
        }
        builtinMonitor.onChange = { [weak self] value in
            self?.builtinBrightness = value
            self?.syncEngine.builtinChanged(value)
        }
        settings.$syncEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                // Runs before the @Published value lands; defer one hop.
                DispatchQueue.main.async { self?.updatePauseState() }
            }
            .store(in: &cancellables)

        displayManager.startObserving()
        builtinMonitor.start()
        startScrollToDim()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            GammaDimmer.restoreAll()
        }
        NSLog("Lonar: brightness notifications %@",
              builtinMonitor.usingNotifications ? "active (watchdog poll 5s)" : "unavailable (poll 0.5s)")
    }

    /// Scroll wheel over the menu bar icon adjusts all external displays.
    /// The status item's window is an AppKit implementation detail of
    /// MenuBarExtra, so match by window class name; if Apple renames it the
    /// feature silently no-ops.
    private var scrollAccumulator: Double = 0
    private func startScrollToDim() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = event.window,
                  String(describing: type(of: window)).contains("StatusBarWindow") else {
                return event
            }
            var delta = event.scrollingDeltaY
            if event.isDirectionInvertedFromDevice { delta = -delta }
            self.scrollAccumulator += delta
            // ~5 scroll points per 1% step keeps trackpads controllable.
            let steps = Int(self.scrollAccumulator / 5)
            if steps != 0 {
                self.scrollAccumulator -= Double(steps * 5)
                self.syncEngine.adjustAll(byPercent: steps)
            }
            return nil
        }
    }

    /// Polling is pointless with no DDC display or with sync off.
    private func updatePauseState() {
        let idle = displayManager.externals.isEmpty || !settings.syncEnabled
        builtinMonitor.setPaused(idle)
    }
}

struct LonarApp: App {
    @StateObject private var state: AppState

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        _state = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        MenuBarExtra("Lonar", systemImage: "sun.max") {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(state.settings)
                .environmentObject(state.displayManager)
                .environmentObject(state.syncEngine)
        }
        .menuBarExtraStyle(.window)
    }
}
