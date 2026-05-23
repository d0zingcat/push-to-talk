# PushToTalk

Swift push-to-talk for Doubao IME voice input on macOS.

Hold **Right Command** to start recording, release to stop, and PushToTalk restores your original input method after Doubao finishes inserting text.

## Quick Start

Install the menu bar app:

```bash
./scripts/install-app.sh
```

Then grant macOS Accessibility and Input Monitoring permissions to `PushToTalk.app` when prompted.

For a background-only LaunchAgent:

```bash
./scripts/install-daemon.sh "豆包输入法"
```

## How It Works

```text
Hold Right Command
  -> record current IME
  -> switch to Doubao IME
  -> wait for the input source switch to settle
  -> trigger Doubao voice input with clean synthetic Option or Fn events

Release Right Command
  -> stop the voice session
  -> restore the previous IME after Doubao has time to insert text
```

The global event tap is listen-only, so physical right Command events still pass through to macOS. Synthetic trigger events are posted separately and do not inherit the held Command flags.

## Project Layout

```text
push-to-talk/
├── Sources/PushToTalk/   # Swift app, daemon, CLI, core helpers, resources
├── scripts/              # install, restart, and uninstall commands
├── packaging/            # Makefile, DMG packaging script, packaging artwork
├── dist/                 # built binary and app bundle
├── tests/                # Swift structure and behavior checks
├── docs/                 # focused user and developer docs
└── README.md
```

## Documentation

- [Installation](docs/installation.md)
- [Configuration](docs/configuration.md)
- [Architecture](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Development](docs/development.md)

## Development

Build:

```bash
make -C packaging
```

Run checks:

```bash
swift tests/check-project-structure.swift
swift tests/check-daemon-release-flow.swift
```
