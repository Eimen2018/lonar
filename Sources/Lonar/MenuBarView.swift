import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var displayManager: DisplayManager
    @EnvironmentObject var syncEngine: SyncEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lonar").font(.headline)
                Spacer()
                Toggle("Sync", isOn: $settings.syncEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: settings.syncEnabled) { _, enabled in
                        if enabled { syncEngine.resync() }
                    }
            }

            Text("Built-in: \(Int((state.builtinBrightness * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            if displayManager.externals.isEmpty {
                Text("No DDC-capable external display found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayManager.externals) { display in
                    DisplayRow(display: display)
                }
            }

            Divider()

            if AppSettings.canManageLoginItem {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.checkbox)
            } else {
                Text("Run from Lonar.app to enable launch at login")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                if let updater = state.updaterController {
                    Button("Check for Updates…") {
                        updater.updater.checkForUpdates()
                    }
                    .font(.caption)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct DisplayRow: View {
    let display: ExternalDisplay
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var syncEngine: SyncEngine
    @State private var manualPercent: Double = 50
    @State private var isDragging = false
    @State private var showCurve = false

    private var statePercent: Int {
        let target = syncEngine.lastTargets[display.id] ?? Int(display.initialValue ?? 50)
        return Int((Double(target) / Double(display.maxBrightness) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(display.name).font(.subheadline).bold()
                Spacer()
                if syncEngine.displayStates[display.id] == .ddcFailed {
                    Label("DDC failed", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(statePercent)%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Slider(value: $manualPercent, in: 0...100) { editing in
                isDragging = editing
                if !editing {
                    syncEngine.setManual(displayID: display.id, percent: manualPercent)
                }
            }
            .controlSize(.small)
            // Keep the knob following auto-sync unless the user is mid-drag.
            .onChange(of: statePercent) { _, newValue in
                if !isDragging { manualPercent = Double(newValue) }
            }

            DisclosureGroup("Curve", isExpanded: $showCurve) {
                CurveEditor(edidUUID: display.edidUUID)
            }
            .font(.caption)
        }
        .onAppear { manualPercent = Double(statePercent) }
    }
}

private struct CurveEditor: View {
    let edidUUID: String
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var syncEngine: SyncEngine

    var body: some View {
        let curve = settings.curve(for: edidUUID)
        VStack(alignment: .leading, spacing: 4) {
            LabeledSlider(label: "Min", value: curve.minPercent, range: 0...90) { newValue in
                var c = settings.curve(for: edidUUID)
                c.minPercent = min(newValue, c.maxPercent - 5)
                apply(c)
            }
            LabeledSlider(label: "Max", value: curve.maxPercent, range: 10...100) { newValue in
                var c = settings.curve(for: edidUUID)
                c.maxPercent = max(newValue, c.minPercent + 5)
                apply(c)
            }
            LabeledSlider(label: "Gamma", value: curve.gamma, range: 0.3...3.0) { newValue in
                var c = settings.curve(for: edidUUID)
                c.gamma = newValue
                apply(c)
            }
        }
        .padding(.top, 4)
    }

    private func apply(_ curve: DisplayCurve) {
        settings.setCurve(curve, for: edidUUID)
        syncEngine.resync()
    }
}

private struct LabeledSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        HStack {
            Text(label).frame(width: 44, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .controlSize(.mini)
            Text(String(format: "%.1f", value))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
        .font(.caption)
    }
}
