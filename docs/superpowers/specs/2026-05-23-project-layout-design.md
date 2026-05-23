# Project Layout Design

## Goal

Move PushToTalk from a flat helper-oriented layout to a clean Swift project layout with source, scripts, packaging, distribution output, tests, and documentation separated by responsibility.

## Target Structure

```text
push-to-talk/
├── Sources/PushToTalk/
│   ├── App/
│   ├── CLI/
│   ├── Core/
│   ├── Daemon/
│   ├── Resources/
│   └── main.swift
├── scripts/
├── packaging/
├── dist/
├── tests/
├── docs/
└── README.md
```

## Design

The Swift source root becomes `Sources/PushToTalk`. Files are grouped by runtime responsibility: menu bar app code in `App`, command parsing in `CLI`, reusable macOS helpers in `Core`, daemon state and event handling in `Daemon`, and bundled resources in `Resources`.

Installer and lifecycle scripts move to `scripts`. Packaging-only files and the Makefile move to `packaging`. Generated binaries and app bundles move to `dist`, replacing the previous mixed-purpose `assets` directory.

The README becomes an overview and quick-start page. Detailed installation, configuration, architecture, troubleshooting, and development notes move into focused files under `docs`.

This is a clean break: root-level install scripts, `swift-helper`, and `assets/pushtotalk` are removed. Canonical commands become `make -C packaging`, `./scripts/install-app.sh`, `./scripts/install-daemon.sh`, and `dist/pushtotalk`.

## Verification

Automated checks must validate the new structure, build paths, docs links, and daemon behavior. CI must build from `packaging`, run the Swift checks, and package artifacts from `dist` and `scripts`.
