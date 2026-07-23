import Foundation
import ServiceManagement

struct DisplayCurve: Codable, Equatable {
    var minPercent: Double = 0
    var maxPercent: Double = 100
    var gamma: Double = 1.0
}

final class AppSettings: ObservableObject {
    private static let curvesKey = "displayCurves"
    private static let syncKey = "syncEnabled"

    @Published var syncEnabled: Bool {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: Self.syncKey) }
    }

    @Published private(set) var curves: [String: DisplayCurve] {
        didSet {
            if let data = try? JSONEncoder().encode(curves) {
                UserDefaults.standard.set(data, forKey: Self.curvesKey)
            }
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert on failure (e.g. running outside a .app bundle).
                launchAtLogin = oldValue
            }
        }
    }

    /// SMAppService needs a real .app bundle in a stable location.
    static var canManageLoginItem: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    init() {
        let defaults = UserDefaults.standard
        syncEnabled = defaults.object(forKey: Self.syncKey) as? Bool ?? true
        if let data = defaults.data(forKey: Self.curvesKey),
           let decoded = try? JSONDecoder().decode([String: DisplayCurve].self, from: data) {
            curves = decoded
        } else {
            curves = [:]
        }
        launchAtLogin = Self.canManageLoginItem && SMAppService.mainApp.status == .enabled
    }

    func curve(for edidUUID: String) -> DisplayCurve {
        curves[edidUUID] ?? DisplayCurve()
    }

    func setCurve(_ curve: DisplayCurve, for edidUUID: String) {
        curves[edidUUID] = curve
    }
}
