# Development

## Build

```bash
make -C packaging
```

Build output is written to:

```text
dist/pushtotalk
dist/PushToTalk.app
```

Clean generated outputs:

```bash
make -C packaging clean
```

## Test

```bash
swift tests/check-project-structure.swift
swift tests/check-daemon-release-flow.swift
```

## Package

```bash
./packaging/package-dmg.sh
```

This writes:

```text
dist/PushToTalk.dmg
```

If `create-dmg` is installed, the package script creates a styled installer window. Otherwise it falls back to `hdiutil`.

## CLI

The built binary supports:

| Command | Purpose |
|---------|---------|
| `dist/pushtotalk daemon [--target <name>]` | Start the background daemon |
| `dist/pushtotalk full-flow --target <name> --delay <ms>` | Run one switch, trigger, wait, restore cycle |
| `dist/pushtotalk restore --target <name>` | Switch to a named input source |
| `dist/pushtotalk check-permission` | Prompt for and verify Accessibility permission |
| `dist/pushtotalk list-sources` | List keyboard input source names |
