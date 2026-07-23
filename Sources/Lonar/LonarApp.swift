import AppKit
import Combine
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

    @Published var builtinBrightness: Float = 0

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.displayManager = DisplayManager()
        self.syncEngine = SyncEngine(settings: settings)
        self.builtinMonitor = BuiltinBrightnessMonitor()

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
        NSLog("Lonar: brightness notifications %@",
              builtinMonitor.usingNotifications ? "active (watchdog poll 5s)" : "unavailable (poll 0.5s)")
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
