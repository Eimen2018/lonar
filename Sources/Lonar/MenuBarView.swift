import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var displayManager: DisplayManager
    @EnvironmentObject var syncEngine: SyncEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            builtinRow

            if displayManager.externals.isEmpty {
                emptyState
            } else {
                ForEach(displayManager.externals) { display in
                    DisplayCard(display: display)
                }
            }

            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled.inverse")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("Lonar")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Spacer()
            Toggle("", isOn: $settings.syncEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .onChange(of: settings.syncEnabled) { _, enabled in
                    if enabled { syncEngine.resync() }
                }
        }
    }

    private var builtinRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Built-in display")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int((state.builtinBrightness * 100).rounded()))%")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(settings.syncEnabled ? Color.accentColor : .secondary)
        }
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No controllable display found")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Connect a DDC-capable or Apple monitor")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(cardShape)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if AppSettings.canManageLoginItem {
                Toggle("Open at login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.caption)
            } else {
                Text("Open at login needs Lonar.app")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let updater = state.updaterController {
                Button {
                    updater.updater.checkForUpdates()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Check for updates")
            }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Lonar")
        }
        .padding(.top, 2)
    }
}

private var cardShape: some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.quaternary.opacity(0.5))
}

private struct DisplayCard: View {
    let display: ExternalDisplay
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var syncEngine: SyncEngine
    @State private var manualPercent: Double = 50
    @State private var isDragging = false
    @State private var showCurve = false

    private var statePercent: Int {
        syncEngine.lastTargets[display.id]
            ?? display.initialValue.map {
                Int((Double($0) / Double(display.maxBrightness) * 100).rounded())
            } ?? 50
    }

    private var isSubZero: Bool { manualPercent < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            titleRow
            brightnessRow
            if let volume = display.volume {
                VolumeRow(display: display, initial: volume)
            }
            if display.supportsDDCExtras {
                InputRow(display: display)
            }
            curveSection
        }
        .padding(10)
        .background(cardShape)
        .onAppear { manualPercent = Double(statePercent) }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(display.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(display.controlLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
            Spacer()
            if syncEngine.displayStates[display.id] == .ddcFailed {
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if isSubZero {
                Label("\(Int(manualPercent))%", systemImage: "moon.fill")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.indigo)
            } else {
                Text("\(statePercent)%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var brightnessRow: some View {
        HStack(spacing: 7) {
            Image(systemName: isSubZero ? "moon.stars.fill" : "sun.min.fill")
                .font(.caption)
                .foregroundStyle(isSubZero ? AnyShapeStyle(.indigo) : AnyShapeStyle(.tertiary))
            Slider(
                value: $manualPercent,
                in: Double(SyncEngine.minPercent)...Double(SyncEngine.maxPercent)
            ) { editing in
                isDragging = editing
                if !editing {
                    syncEngine.setManual(displayID: display.id, percent: manualPercent)
                }
            }
            .controlSize(.small)
            .tint(isSubZero ? .indigo : .accentColor)
            .onChange(of: statePercent) { _, newValue in
                if !isDragging { manualPercent = Double(newValue) }
            }
            Image(systemName: "sun.max.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var curveSection: some View {
        DisclosureGroup(isExpanded: $showCurve) {
            CurveEditor(edidUUID: display.edidUUID)
        } label: {
            Label("Sync curve", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VolumeRow: View {
    let display: ExternalDisplay
    let initial: (current: UInt16, max: UInt16)
    @EnvironmentObject var syncEngine: SyncEngine
    @State private var volume: Double = -1
    @State private var muted = false
    @State private var seeded = false

    private var volumePercent: Int {
        Int((volume / Double(initial.max) * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 7) {
            Button {
                muted.toggle()
                syncEngine.sendCommand(
                    displayID: display.id, command: VCP.audioMute,
                    value: muted ? 1 : 2)
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(muted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .frame(width: 14)
            }
            .buttonStyle(.borderless)
            .help(muted ? "Unmute" : "Mute")
            Slider(value: $volume, in: 0...Double(initial.max)) { editing in
                if !editing {
                    if muted {
                        // Adjusting volume implies the user wants sound back.
                        muted = false
                        syncEngine.sendCommand(
                            displayID: display.id, command: VCP.audioMute, value: 2)
                    }
                    syncEngine.sendCommand(
                        displayID: display.id, command: VCP.volume,
                        value: UInt16(volume.rounded()))
                }
            }
            .controlSize(.small)
            .tint(muted ? .gray : .accentColor)
            Text(muted ? "Muted" : "\(volumePercent)%")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(muted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 42, alignment: .trailing)
        }
        .onAppear {
            if !seeded {
                seeded = true
                volume = Double(initial.current)
                muted = display.mutedAtDiscovery ?? false
            }
        }
    }
}

private struct InputRow: View {
    let display: ExternalDisplay
    @EnvironmentObject var syncEngine: SyncEngine

    var body: some View {
        HStack {
            Label("Input", systemImage: "cable.connector.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(InputSource.allCases) { source in
                    Button {
                        syncEngine.sendCommand(
                            displayID: display.id, command: VCP.inputSelect,
                            value: source.rawValue)
                    } label: {
                        if display.currentInput == source.rawValue {
                            Label(source.label, systemImage: "checkmark")
                        } else {
                            Text(source.label)
                        }
                    }
                }
            } label: {
                Text(InputSource(rawValue: display.currentInput ?? 0)?.label ?? "Switch")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct CurveEditor: View {
    let edidUUID: String
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var syncEngine: SyncEngine

    var body: some View {
        let curve = settings.curve(for: edidUUID)
        VStack(alignment: .leading, spacing: 5) {
            LabeledSlider(
                label: "Min", value: curve.minPercent, range: -50...90,
                format: { "\(Int($0))%" }
            ) { newValue in
                var c = settings.curve(for: edidUUID)
                c.minPercent = min(newValue, c.maxPercent - 5)
                apply(c)
            }
            LabeledSlider(
                label: "Max", value: curve.maxPercent, range: 10...100,
                format: { "\(Int($0))%" }
            ) { newValue in
                var c = settings.curve(for: edidUUID)
                c.maxPercent = max(newValue, c.minPercent + 5)
                apply(c)
            }
            LabeledSlider(
                label: "Shape", value: curve.gamma, range: 0.3...3.0,
                format: { String(format: "γ %.1f", $0) }
            ) { newValue in
                var c = settings.curve(for: edidUUID)
                c.gamma = newValue
                apply(c)
            }
        }
        .padding(.top, 6)
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
    let format: (Double) -> String
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .controlSize(.mini)
            Text(format(value))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
