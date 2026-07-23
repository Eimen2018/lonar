# Lonar

A free, open-source replacement for Lunar Pro's **Sync Mode**: a macOS menu bar app
that keeps external monitors' hardware brightness (via DDC/CI) in sync with the
MacBook's built-in display brightness — which macOS already auto-adjusts using
the ambient light sensor. Net effect: your external monitor adapts to ambient
light for free.

Works on any Apple Silicon Mac (M1 → M4, incl. Pro/Max/Ultra multi-display
setups). Not sandboxed, not App Store material — it uses private APIs, like
every app in this category.

## Install

Download `Lonar.app.zip` from the
[latest release](https://github.com/Eimen2018/lonar/releases/latest), unzip,
and move `Lonar.app` to `/Applications`.

The app is ad-hoc signed (no paid Apple Developer ID), so macOS will warn
that it "couldn't verify" the download. Two ways past it:

- Try to open it, dismiss the dialog, then System Settings →
  **Privacy & Security** → **Open Anyway**, or
- clear the quarantine flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Lonar.app
```

(Or skip all of this by building from source below.)

## Build & run from source

```bash
swift build && .build/debug/Lonar        # run the menu bar app
```

Install as a real app (required for launch-at-login):

```bash
Scripts/make-app.sh --install
```

## CLI (debug tools built into the same binary)

```
Lonar displays       # list DDC-capable external displays (with EDID UUID)
Lonar ddc-get        # read brightness via DDC
Lonar ddc-set 70     # set external brightness 0-100
Lonar builtin-get    # read built-in panel brightness (0.0-1.0)
Lonar builtin-set .5 # set built-in panel brightness (debug)
```

## How it works

- **Built-in brightness**: push notifications from the private
  `DisplayServices` framework (`DisplayServicesRegisterForBrightnessChangeNotifications`,
  signature per Lunar's bridging header) with a leeway-coalesced 5 s watchdog
  poll; falls back to 500 ms polling if registration fails. Polling pauses
  entirely when no DDC display is connected or sync is off. All symbols
  `dlopen`/`dlsym`'d, nil-safe.
- **External control**: DDC/CI (VCP 0x10) over I2C using the undocumented
  `IOAVService` API. Display ↔ DDC-port matching (EDID UUID + heuristics) and
  checksummed I2C comes from a vendored copy of
  [waydabber/AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC)
  (MIT — see `Sources/Lonar/Vendor/LICENSE-AppleSiliconDDC`).
- **Sync engine**: builtin 0–1 → `min + (max−min)·b^gamma` → integer DDC value.
  Change-gated (zero I2C traffic at steady state), coalesced, ramped at ≤8
  units per 100 ms per display. 5 consecutive write failures → "DDC failed"
  state with 30 s reprobe.
- **Per-display curves** (min/max/gamma) are stored by EDID UUID, so settings
  follow the monitor across machines and ports.
- Hot-plug / wake: rescans (2 s debounce) and recreates DDC services — refs are
  never reused across sleep.

## Requirements

- Apple Silicon Mac (M1 or newer, incl. Pro/Max/Ultra)
- macOS 14 Sonoma or newer
- An external monitor that supports DDC/CI (most do), connected via
  USB-C/Thunderbolt/DisplayPort

## Known limitations

- The built-in HDMI port on base M1/M2 Macs doesn't pass DDC cleanly
  (hardware limitation shared with Lunar/MonitorControl). USB-C/Thunderbolt →
  DisplayPort is reliable. DisplayLink adapters are unsupported.
- Deferred for later: volume/contrast/input control, software gamma dimming
  fallback, XDR.

## Disclaimer

Lonar relies on undocumented macOS APIs (`IOAVService`, `DisplayServices`) —
the same ones used by Lunar, MonitorControl, and BetterDisplay. Apple could
change them in any release; every symbol is loaded defensively so the app
degrades gracefully rather than crashing. Use at your own risk.

## Credits

- [waydabber/AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC)
  (MIT) — vendored DDC/CI + display-matching layer.
- [Lunar](https://lunar.fyi/) and
  [MonitorControl](https://github.com/MonitorControl/MonitorControl) — prior
  art that mapped out this territory. If you want more than brightness sync,
  buy Lunar; it's excellent.

## License

MIT — see [LICENSE](LICENSE).
