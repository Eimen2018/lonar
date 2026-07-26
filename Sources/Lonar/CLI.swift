import CoreGraphics
import Foundation
import SwiftUI

/// Debug/smoke-test subcommands. The same binary runs these when given args
/// and only starts the menu bar UI when launched bare.
enum CLI {
    static func run(arguments: [String]) -> Never {
        let cmd = arguments.count > 1 ? arguments[1] : "help"
        switch cmd {
        case "displays":
            let displays = DisplayManager.scan()
            if displays.isEmpty {
                print("No DDC-capable external displays found.")
            }
            for d in displays {
                let current = d.initialValue.map(String.init) ?? "?"
                var extras = ""
                if let v = d.volume { extras += "  volume=\(v.current)/\(v.max)" }
                if let i = d.currentInput { extras += "  input=\(i)" }
                print("[\(d.id)] \(d.name) (\(d.controlLabel))  uuid=\(d.edidUUID)  brightness=\(current)/\(d.maxBrightness)\(extras)")
            }
            exit(0)

        case "ddc-get":
            for d in DisplayManager.scan() {
                switch d.control {
                case .ddc(let service):
                    if let r = AppleSiliconDDC.read(service: service, command: VCP.brightness) {
                        print("\(d.name): \(r.current)/\(r.max)")
                    } else {
                        print("\(d.name): DDC read failed")
                    }
                case .appleNative:
                    let value = DisplayServices.brightness(for: d.id)
                        .map { String(Int(($0 * 100).rounded())) } ?? "?"
                    print("\(d.name): \(value)/100 (Apple native)")
                }
            }
            exit(0)

        case "ddc-set":
            guard arguments.count > 2, let value = UInt16(arguments[2]) else {
                print("usage: Lonar ddc-set <0-100>")
                exit(1)
            }
            for d in DisplayManager.scan() {
                let ok: Bool
                switch d.control {
                case .ddc(let service):
                    ok = AppleSiliconDDC.write(service: service, command: VCP.brightness, value: value)
                case .appleNative:
                    ok = DisplayServices.setBrightness(Float(value) / 100.0, for: d.id)
                }
                print("\(d.name): write \(value) -> \(ok ? "ok" : "FAILED")")
            }
            exit(0)

        case "volume-set":
            guard arguments.count > 2, let value = UInt16(arguments[2]) else {
                print("usage: Lonar volume-set <0-100>")
                exit(1)
            }
            for d in DisplayManager.scan() where d.supportsDDCExtras {
                if case .ddc(let service) = d.control {
                    let ok = AppleSiliconDDC.write(service: service, command: VCP.volume, value: value)
                    print("\(d.name): volume \(value) -> \(ok ? "ok" : "FAILED")")
                }
            }
            exit(0)

        case "input-set":
            guard arguments.count > 2, let value = UInt16(arguments[2]) else {
                print("usage: Lonar input-set <code>  (15/16=DisplayPort, 17/18=HDMI, 27=USB-C)")
                exit(1)
            }
            for d in DisplayManager.scan() where d.supportsDDCExtras {
                if case .ddc(let service) = d.control {
                    let ok = AppleSiliconDDC.write(service: service, command: VCP.inputSelect, value: value)
                    print("\(d.name): input \(value) -> \(ok ? "ok" : "FAILED")")
                }
            }
            exit(0)

        case "dim":
            // Full percent domain incl. sub-zero, e.g. `Lonar dim -30`.
            guard arguments.count > 2, let pct = Int(arguments[2]),
                  (SyncEngine.minPercent...SyncEngine.maxPercent).contains(pct) else {
                print("usage: Lonar dim <\(SyncEngine.minPercent)..\(SyncEngine.maxPercent)>")
                exit(1)
            }
            for d in DisplayManager.scan() {
                let hardware = max(0, pct)
                let ok: Bool
                switch d.control {
                case .ddc(let service):
                    let value = UInt16((Double(hardware) / 100.0 * Double(d.maxBrightness)).rounded())
                    ok = AppleSiliconDDC.write(service: service, command: VCP.brightness, value: value)
                case .appleNative:
                    ok = DisplayServices.setBrightness(Float(hardware) / 100.0, for: d.id)
                }
                let multiplier = pct >= 0 ? Float(1.0) : 1.0 + Float(pct) / 50.0 * 0.8
                GammaDimmer.setMultiplier(multiplier, for: d.id)
                print("\(d.name): dim \(pct)% (gamma ×\(multiplier)) -> \(ok ? "ok" : "FAILED")")
            }
            exit(0)

        case "preview":
            // Dev tool: render the popover to a PNG without opening the UI.
            // The CLI entry point runs on the main thread.
            MainActor.assumeIsolated {
                let out = arguments.count > 2 ? arguments[2] : "popover-preview.png"
                let state = AppState()
                let view = MenuBarView()
                    .environmentObject(state)
                    .environmentObject(state.settings)
                    .environmentObject(state.displayManager)
                    .environmentObject(state.syncEngine)
                    .background(.regularMaterial)
                    .preferredColorScheme(.dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                    print("wrote \(out)")
                    exit(0)
                }
                print("render failed")
                exit(1)
            }
            exit(1)

        case "builtin-set":
            guard arguments.count > 2, let value = Float(arguments[2]), (0...1).contains(value) else {
                print("usage: Lonar builtin-set <0.0-1.0>")
                exit(1)
            }
            guard let id = BuiltinBrightnessMonitor.findBuiltinDisplay() else {
                print("No built-in display found")
                exit(1)
            }
            let ok = DisplayServices.setBrightness(value, for: id)
            print("builtin set \(value) -> \(ok ? "ok" : "FAILED")")
            exit(ok ? 0 : 1)

        case "builtin-get":
            let monitor = BuiltinBrightnessMonitor()
            if let value = monitor.currentBrightness() {
                print(String(format: "builtin brightness: %.3f", value))
                exit(0)
            } else {
                print("Could not read built-in brightness (DisplayServices unavailable?)")
                exit(1)
            }

        default:
            print("""
            Lonar — external monitor brightness sync
            usage: Lonar [command]
              (no command)   start the menu bar app
              displays       list DDC-capable external displays
              ddc-get        read brightness via DDC from each external display
              ddc-set <n>    set DDC brightness (0-100) on each external display
              dim <n>        set brightness incl. sub-zero (-50..100)
              volume-set <n> set speaker volume via DDC (0-100)
              input-set <n>  switch input source (15/16=DP, 17/18=HDMI, 27=USB-C)
              builtin-get    read built-in display brightness
            """)
            exit(cmd == "help" ? 0 : 1)
        }
    }
}
