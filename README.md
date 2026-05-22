# pushtotalk

Push-to-talk for Doubao IME voice input on macOS — no Hammerspoon, no Raycast required.

Hold **Right Command** to start recording, release to stop. The original input method is automatically restored 2 seconds later.

---

## Why this exists

Doubao IME (豆包输入法) has excellent free voice recognition, but a poor daily-driver keyboard experience. The goal is to use Doubao only for voice input while keeping your preferred IME for everything else.

The original approach used [Hammerspoon](https://www.hammerspoon.org/) for global key monitoring. This project reimplements the same behaviour as a standalone compiled binary — no third-party automation framework needed.

---

## How it works

```
Hold Right Command
  └─ record current IME
  └─ switch to Doubao IME
  └─ after 300ms: double-tap Right Option  →  Doubao starts recording

Release Right Command
  └─ double-tap Right Option               →  Doubao stops recording
  └─ after 2s: restore original IME
```

The 2-second post-release delay gives Doubao time to finish speech recognition and insert the text before the IME switches away.

### Technical stack

| Layer | What | Why |
|-------|------|-----|
| `swift-helper/main.swift` | Swift CLI binary | macOS-native TIS and CGEvent APIs |
| `CGEventTap` | Global key monitor | Intercepts `flagsChanged` events system-wide — same mechanism Hammerspoon uses |
| `TIS` API (Carbon) | Input source switching | `TISSelectInputSource` / `TISCopyCurrentKeyboardInputSource` |
| `CGEvent` (CoreGraphics) | Key simulation | Posts `flagsChanged` events for Right Option (keyCode 61) to `.cgSessionEventTap` |
| LaunchAgent | Auto-start | `~/Library/LaunchAgents/com.pushtotalk.daemon.plist` with `KeepAlive: true` |

### Key implementation notes

**Why `flagsChanged` and not `keyDown`/`keyUp`?**  
Modifier keys (Option, Command, Shift…) produce `flagsChanged` events, not `keyDown`. Doubao's voice trigger listens for this event type. Using `keyDown` for Option is silently ignored.

**Why track key state internally instead of reading `flags.cmd`?**  
macOS can coalesce or drop modifier flags in edge cases. Tracking press/release via an internal boolean (`daemonRightCmdIsDown`) is more reliable — the same fix Hammerspoon applies.

**Why the 300ms press delay before triggering voice?**  
Matches `OPTION_PRESS_DELAY = 0.30` from the original Hammerspoon config. Gives the IME switch time to settle before the double-tap arrives.

**Why 180ms between the two Option taps?**  
Matches `OPTION_DOUBLE_TAP_INTERVAL = 0.18` from Hammerspoon. Doubao's double-tap detector rejects intervals that are too short (≤18ms is not recognised).

**Right Option flags: `maskAlternate | 0x00000040`**  
`0x00000040` is `NX_DEVICERALTKEYMASK` — the device-specific bit that identifies the right Option key. Without it, the event looks like a generic (left) Option press.

---

## Project structure

```
pushtotalk/
├── swift-helper/
│   ├── main.swift          # All logic: daemon, full-flow, restore subcommands
│   └── Makefile            # swiftc build → assets/pushtotalk
├── assets/
│   └── pushtotalk          # Compiled binary (committed, no Xcode needed to install)
├── src/
│   └── trigger.ts          # Raycast no-view command (alternative entrypoint)
├── install-daemon.sh       # Compile + install LaunchAgent
├── uninstall-daemon.sh     # Stop + remove LaunchAgent
└── package.json            # Raycast extension manifest (optional path only)
```

---

## Prerequisites

- macOS (tested on macOS 15+)
- Doubao IME installed and added to input sources
- Xcode Command Line Tools — only needed to **rebuild** the binary: `xcode-select --install`
- The compiled binary (`assets/pushtotalk`) is committed, so end users don't need Xcode

---

## Installation

```bash
git clone <this-repo>
cd pushtotalk
./install-daemon.sh
```

If your Doubao IME has a different localised name, pass it as an argument:

```bash
./install-daemon.sh "豆包输入法"
```

The script:
1. Compiles `swift-helper/main.swift` → `assets/pushtotalk`
2. Copies the binary to `~/.local/bin/pushtotalk`
3. Writes `~/Library/LaunchAgents/com.pushtotalk.daemon.plist`
4. Loads the LaunchAgent (starts immediately, restarts on crash, survives reboots)

### First-run: grant Accessibility permission

The daemon uses `CGEventTap` to read global keyboard events. macOS requires explicit user consent.

Go to **System Settings → Privacy & Security → Accessibility** and add the terminal or shell you ran `install-daemon.sh` from. If the daemon is already running via LaunchAgent, add the `pushtotalk` binary directly.

You can verify the permission is in effect by checking the daemon log:

```bash
tail -f /tmp/pushtotalk-daemon.log
# Should show: doubao-ime daemon started (target: 豆包输入法)
```

---

## Usage

Once installed: **hold Right Command to talk, release to stop**.

The daemon runs silently in the background. There is no UI.

### Uninstall

```bash
./uninstall-daemon.sh
```

Stops the daemon, removes the LaunchAgent plist, and deletes `~/.local/bin/pushtotalk`.

---

## Troubleshooting

**Voice input doesn't start when I hold Right Command**

1. Check accessibility permission (see above).
2. Confirm your Doubao IME name matches the `--target` value in the LaunchAgent plist:

```bash
# List all installed input source names
swift - <<'EOF'
import Carbon
let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
for src in list {
    if let ptr = TISGetInputSourceProperty(src, kTISPropertyLocalizedName) {
        print(Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String)
    }
}
EOF
```

Find the Doubao entry, then re-run `./install-daemon.sh "<exact name>"`.

3. Check error log: `cat /tmp/pushtotalk-daemon.err`

**IME doesn't switch back after recording**

The restore fires 2 seconds after releasing Right Command (`DAEMON_RESTORE_DELAY = 2.0`). If Doubao is still inserting text at that point, increase the delay by editing `main.swift` and re-running `./install-daemon.sh`.

**Daemon stops working after a while**

The LaunchAgent has `KeepAlive: true` so it restarts automatically. If it keeps dying, check `/tmp/pushtotalk-daemon.err` for the error. The most common cause is losing accessibility permission after a macOS update.

---

## Configuration

All timing constants are in `swift-helper/main.swift`:

```swift
let DAEMON_OPTION_PRESS_DELAY: TimeInterval = 0.30   // delay before voice starts after keydown
let DAEMON_OPTION_TAP_INTERVAL: TimeInterval = 0.18  // interval between the two Option taps
let DAEMON_RESTORE_DELAY: TimeInterval = 2.0          // delay before IME restore after keyup
```

After editing, reinstall:

```bash
./install-daemon.sh
```

---

## Binary subcommands

The binary has three subcommands:

| Subcommand | Purpose |
|-----------|---------|
| `pushtotalk daemon [--target <name>]` | Start the background daemon (used by LaunchAgent) |
| `pushtotalk full-flow --target <name> --delay <ms>` | One-shot trigger + timed restore (used by Raycast extension) |
| `pushtotalk restore --target <name>` | Switch to a named input source (utility) |

---

## Raycast extension (optional)

`src/trigger.ts` and `package.json` provide a Raycast `no-view` command as an alternative entrypoint. It spawns `assets/pushtotalk full-flow` as a detached background process, waits 300ms to catch immediate errors, then shows a HUD.

To use it: install Raycast, run `npm install && npm run dev`, and bind a global shortcut to "触发豆包语音输入" in Raycast settings. The daemon approach is recommended over this for daily use.

---

## Origin

Ported from [Doubao-ime-hammerspoon](https://github.com/Paxxs/Doubao-ime-hammerspoon), which implements the same push-to-talk logic in Lua using Hammerspoon's `hs.eventtap`. The timing constants (`0.30`, `0.18`, `2.0`) are taken directly from that project.
