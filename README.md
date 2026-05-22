# PushToTalk

Swift-only push-to-talk for Doubao IME voice input on macOS.

Hold **Right Command** to start recording, release to stop. The original input method is restored 3 seconds later.

## Why this exists

Doubao IME has good voice recognition, but it is not always a good daily-driver keyboard input method. This helper lets you keep your normal IME active and only switch to Doubao while recording.

## How it works

```text
Hold Right Command
  -> record current IME
  -> switch to Doubao IME
  -> wait 300ms for the input source switch to settle
  -> double-tap Right Option to start recording

Release Right Command
  -> Doubao stops recording from the released hold key
  -> after 3s: restore original IME (or restore immediately if any key is pressed to start typing)
```

The delay after release gives Doubao time to finish recognition and insert text before the input method switches away. If you start typing manually during this 3-second window, the tool detects the keystrokes and restores your original input method immediately.

## Implementation

| Layer | File | Purpose |
|-------|------|---------|
| GUI & CLI | `swift-helper/main.swift` | Input source switching, listen-only global key event tap, Right Option simulation, command parsing, SwiftUI Menu Bar UI |
| Build | `swift-helper/Makefile` | Compiles the helper and packages `assets/PushToTalk.app` |
| GUI install | `install-app.sh` | Builds, installs, and launches the GUI app |
| GUI uninstall | `uninstall-app.sh` | Removes the GUI app and login items |
| LaunchAgent install | `install-daemon.sh` | Builds, installs, and loads the background CLI daemon |
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
- After switching to Doubao, the daemon waits another 300ms before tapping Right Option so the target IME can receive the trigger.
- If macOS disables the event tap repeatedly, the daemon exits with code 70 instead of continually touching the input event path.
- The LaunchAgent uses `ThrottleInterval` to avoid rapid restart loops.
- If the target IME cannot be selected, the current press is abandoned and no simulated Option events are posted.

## Project structure

```text
push-to-talk/
├── swift-helper/
│   ├── main.swift
│   ├── Info.plist
│   └── Makefile
├── assets/
│   ├── pushtotalk
│   └── PushToTalk.app/
├── tests/
│   ├── check-daemon-release-flow.swift
│   └── check-swift-only-project.swift
├── install-app.sh
├── uninstall-app.sh
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

### GUI App (Recommended)

To install the native Menu Bar GUI app:

```bash
./install-app.sh
```

The GUI installer:
1. Compiles the Swift helper and packages the `PushToTalk.app` bundle in `assets/`.
2. Copies the app to `/Applications` (or `~/Applications`).
3. Stops any conflicting legacy CLI LaunchAgents.
4. Launches the GUI app.

Once launched, click the microphone/waveform icon in the system menu bar to select your target voice input method and customize delays dynamically.

### CLI Daemon (Background LaunchAgent)

If you prefer running a pure CLI daemon in the background without any GUI:

```bash
./install-daemon.sh
```

If your target voice input method has a different localized name, pass it to the installer:

```bash
./install-daemon.sh "豆包输入法"
```

The CLI installer:
1. Compiles the Swift helper.
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

## Privacy Permissions

macOS may require two privacy permissions:

- Accessibility, because the daemon posts Right Option events to trigger Doubao.
- Input Monitoring, because the daemon observes global right Command key events.

Grant both permissions to:

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
~/Library/Logs/pushtotalk/pushtotalk-daemon.log
~/Library/Logs/pushtotalk/pushtotalk-daemon.err
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
| `pushtotalk list-sources` | List all available keyboard input source names |

## Configuration

You can customize trigger keys, simulated keys, and various delays by creating a JSON configuration file at `~/.config/pushtotalk/config.json`.

Example configuration with all default values:

```json
{
  "target_ime": "豆包输入法",
  "trigger_keycode": 54,
  "trigger_flag_raw": 16,
  "simulate_keycode": 61,
  "simulate_flag_raw": 64,
  "restore_delay": 3.0,
  "settle_delay": 0.3,
  "option_tap_interval": 0.18,
  "option_press_delay": 0.3
}
```

### Parameter Reference

*   `target_ime`: The name of the target voice IME (default: `"豆包输入法"`).
*   `trigger_keycode`: Virtual key code to hold to talk (default: `54` for Right Command).
*   `trigger_flag_raw`: Device raw flag mask for the hold key (default: `16` / `0x00000010` for Right Command).
*   `simulate_keycode`: Virtual key code to simulate (default: `61` for Right Option).
*   `simulate_flag_raw`: Device raw flag mask for the simulated key (default: `64` / `0x00000040` for Right Option).
*   `restore_delay`: Delay in seconds before restoring original input source (default: `3.0`).
*   `settle_delay`: Delay in seconds after IME switch before simulating taps (default: `0.3`).
*   `option_tap_interval`: Delay in seconds between simulated key taps (default: `0.18`).
*   `option_press_delay`: Delay in seconds the hold key must be kept down to trigger the IME switch (default: `0.3`).

After creating or modifying the configuration file, restart the daemon to apply changes:

```bash
./restart-daemon.sh
```

## Troubleshooting

**Voice input does not start**

Check the error log:

```bash
cat ~/Library/Logs/pushtotalk/pushtotalk-daemon.err
```

If it says Accessibility permission is missing, grant permission to `~/.local/bin/pushtotalk`, then reload the LaunchAgent.

If the daemon logs right Command events and `posted right-option tap` but Doubao does not open voice input, re-check Accessibility for the installed binary. Without that permission, the helper may run far enough to observe keys but macOS can still block the synthetic Right Option events.

If the log says the event tap was disabled repeatedly and the daemon exited, check for system-wide input lag or permission changes, then restart with:

```bash
./restart-daemon.sh
```

**The target IME is not found**

List installed input source names:

```bash
pushtotalk list-sources
```

Or if running the uninstalled/built asset directly:

```bash
assets/pushtotalk list-sources
```

Then reinstall with the exact Doubao name:

```bash
./install-daemon.sh "<exact name>"
```

**IME restores too early**

You can increase the restore delay by setting `"restore_delay"` in `~/.config/pushtotalk/config.json` (e.g., to `4.0`), then run `./restart-daemon.sh`.

## Uninstall

### GUI App

To completely uninstall the GUI app and remove its autostart plist:

```bash
./uninstall-app.sh
```

### CLI Daemon

To stop and uninstall the legacy CLI background LaunchAgent and helper binary:

```bash
./uninstall-daemon.sh
```

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
