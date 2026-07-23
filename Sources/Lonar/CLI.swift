import CoreGraphics
import Foundation

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
                print("[\(d.id)] \(d.name)  edid=\(d.edidUUID)  brightness=\(current)/\(d.maxBrightness)")
            }
            exit(0)

        case "ddc-get":
            for d in DisplayManager.scan() {
                if let r = AppleSiliconDDC.read(service: d.service, command: VCP.brightness) {
                    print("\(d.name): \(r.current)/\(r.max)")
                } else {
                    print("\(d.name): DDC read failed")
                }
            }
            exit(0)

        case "ddc-set":
            guard arguments.count > 2, let value = UInt16(arguments[2]) else {
                print("usage: Lonar ddc-set <0-100>")
                exit(1)
            }
            for d in DisplayManager.scan() {
                let ok = AppleSiliconDDC.write(service: d.service, command: VCP.brightness, value: value)
                print("\(d.name): write \(value) -> \(ok ? "ok" : "FAILED")")
            }
            exit(0)

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
              builtin-get    read built-in display brightness
            """)
            exit(cmd == "help" ? 0 : 1)
        }
    }
}
