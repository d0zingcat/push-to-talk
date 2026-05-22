# pushtotalk

Swift-only push-to-talk for Doubao IME voice input on macOS.

Hold **Right Command** to start recording, release to stop. The original input method is restored 3 seconds later.

## Why this exists

Doubao IME has good voice recognition, but it is not always a good daily-driver keyboard input method. This helper lets you keep your normal IME active and only switch to Doubao while recording.

## How it works

```text
Hold Right Command
  -> record current IME
  -> switch to Doubao IME
  -> after 300ms: double-tap Right Option to start recording

Release Right Command
  -> double-tap Right Option to stop recording
  -> after 3s: restore original IME
```

The delay after release gives Doubao time to finish recognition and insert text before the input method switches away.

## Implementation

| Layer | File | Purpose |
|-------|------|---------|
| Swift CLI | `swift-helper/main.swift` | Input source switching, listen-only global key event tap, Right Option simulation, command parsing |
| Build | `swift-helper/Makefile` | Compiles the helper to `assets/pushtotalk` |
| LaunchAgent install | `install-daemon.sh` | Builds, installs, and loads the background daemon |
| LaunchAgent restart | `restart-daemon.sh` | Reloads the daemon without rebuilding or replacing the binary |
| LaunchAgent uninstall | `uninstall-daemon.sh` | Stops and removes the daemon |

The daemon uses:

- `CGEventTap` in listen-only mode to observe global `flagsChanged` events without consuming or modifying system input.
- `TISSelectInputSource` and `TISCopyCurrentKeyboardInputSource` to switch IMEs.
- `CGEvent` to post Right Option `flagsChanged` events.

## Stability Guards

The daemon is designed to fail conservatively:

- The event tap is listen-only, so right Command events still pass through to the system.
- Short right Command taps do not switch IMEs. The daemon only activates after the key remains down for 300ms.
- If macOS disables the event tap repeatedly, the daemon exits with code 70 instead of continually touching the input event path.
- The LaunchAgent uses `ThrottleInterval` to avoid rapid restart loops.
- If the target IME cannot be selected, the current press is abandoned and no simulated Option events are posted.

## Project structure

```text
pushtotalk/
├── swift-helper/
│   ├── main.swift
│   └── Makefile
├── assets/
│   └── pushtotalk
├── tests/
│   ├── check-daemon-release-flow.swift
│   └── check-swift-only-project.swift
├── install-daemon.sh
├── restart-daemon.sh
├── uninstall-daemon.sh
└── README.md
```

## Prerequisites

- macOS
- Doubao IME installed and added to input sources
- Xcode Command Line Tools, only needed to rebuild: `xcode-select --install`

## Install

```bash
./install-daemon.sh
```

If your Doubao IME has a different localized name, pass the exact name:

```bash
./install-daemon.sh "豆包输入法"
```

The installer:

1. Compiles `swift-helper/main.swift` to `assets/pushtotalk`.
2. Copies the binary to `~/.local/bin/pushtotalk`.
3. Optionally signs the installed binary if `PUSHTOTALK_CODESIGN_IDENTITY` is set.
4. Writes `~/Library/LaunchAgents/com.pushtotalk.daemon.plist`.
5. Loads the LaunchAgent.

## Stable Code Signing

macOS Accessibility permission can be invalidated when the installed binary is rebuilt with a different signing identity. To reduce repeated permission prompts, sign the installed binary with a stable local or Developer ID code signing identity.

List signing identities:

```bash
security find-identity -v -p codesigning
```

Install with signing:

```bash
PUSHTOTALK_CODESIGN_IDENTITY="<identity name or hash>" ./install-daemon.sh
```

The install script signs `~/.local/bin/pushtotalk` after copying it. Use the same `PUSHTOTALK_CODESIGN_IDENTITY` whenever you reinstall a rebuilt binary.

## Accessibility Permission

macOS requires Accessibility permission because the daemon reads global keyboard events and posts Right Option events.

Grant permission to:

```text
~/.local/bin/pushtotalk
```

Then reload the daemon:

```bash
./restart-daemon.sh
```

Avoid reinstalling immediately after granting permission unless you need a newly built binary. macOS can treat a freshly compiled ad-hoc signed binary as a new program and require permission again.

## Usage

Once installed, hold **Right Command** to talk and release it to stop.

The daemon runs in the background. Logs are written to:

```text
/tmp/pushtotalk-daemon.log
/tmp/pushtotalk-daemon.err
```

Restart the daemon without rebuilding or replacing the binary:

```bash
./restart-daemon.sh
```

## CLI

The binary supports these subcommands:

| Command | Purpose |
|---------|---------|
| `pushtotalk daemon [--target <name>]` | Start the background daemon |
| `pushtotalk full-flow --target <name> --delay <ms>` | Run one switch, trigger, wait, restore cycle |
| `pushtotalk restore --target <name>` | Switch to a named input source |
| `pushtotalk check-permission` | Prompt for and verify Accessibility permission |

## Troubleshooting

**Voice input does not start**

Check the error log:

```bash
cat /tmp/pushtotalk-daemon.err
```

If it says Accessibility permission is missing, grant permission to `~/.local/bin/pushtotalk`, then reload the LaunchAgent.

If the log says the event tap was disabled repeatedly and the daemon exited, check for system-wide input lag or permission changes, then restart with:

```bash
./restart-daemon.sh
```

**The target IME is not found**

List installed input source names:

```bash
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

Then reinstall with the exact Doubao name:

```bash
./install-daemon.sh "<exact name>"
```

**IME restores too early**

The restore delay is controlled by `DAEMON_RESTORE_DELAY` in `swift-helper/main.swift`. Increase it and reinstall.

## Uninstall

```bash
./uninstall-daemon.sh
```

This stops the daemon, removes the LaunchAgent plist, and deletes `~/.local/bin/pushtotalk`.

## Development

Build:

```bash
make -C swift-helper
```

Run checks:

```bash
swift tests/check-daemon-release-flow.swift
swift tests/check-swift-only-project.swift
```
