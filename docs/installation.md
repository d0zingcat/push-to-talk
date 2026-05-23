# Installation

## Prerequisites

- macOS
- Doubao IME installed and added to input sources
- Xcode Command Line Tools for building: `xcode-select --install`

## Menu Bar App

```bash
./scripts/install-app.sh
```

The installer builds `dist/PushToTalk.app`, copies it to `/Applications` or `~/Applications`, signs it, stops any legacy CLI LaunchAgent, and launches the app.

Click the waveform icon in the menu bar to select the target input method and adjust delays.

## CLI Daemon

```bash
./scripts/install-daemon.sh "豆包输入法"
```

The installer builds `dist/pushtotalk`, copies it to `~/.local/bin/pushtotalk`, signs it, writes `~/Library/LaunchAgents/com.pushtotalk.daemon.plist`, and loads the LaunchAgent.

Restart without rebuilding:

```bash
./scripts/restart-daemon.sh
```

## Stable Code Signing

macOS privacy permissions can be invalidated when a rebuilt binary has a different signing identity. To reduce repeated permission prompts, install with a stable signing identity:

```bash
security find-identity -v -p codesigning
PUSHTOTALK_CODESIGN_IDENTITY="<identity name or hash>" ./scripts/install-daemon.sh
```

The GUI installer also honors `PUSHTOTALK_CODESIGN_IDENTITY`.

## Privacy Permissions

Grant both permissions:

- Accessibility, because PushToTalk posts synthetic trigger events.
- Input Monitoring, because PushToTalk observes global right Command events.

For the GUI app, grant permission to `PushToTalk.app`.

For the CLI daemon, grant permission to `~/.local/bin/pushtotalk`.

After granting daemon permissions, run:

```bash
./scripts/restart-daemon.sh
```

## Uninstall

GUI app:

```bash
./scripts/uninstall-app.sh
```

CLI daemon:

```bash
./scripts/uninstall-daemon.sh
```
