# Project Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the project into a clean Swift source, scripts, packaging, dist, tests, and docs layout.

**Architecture:** Move source files into `Sources/PushToTalk` grouped by responsibility, move operational scripts into `scripts`, move build and DMG packaging files into `packaging`, and use `dist` for generated artifacts. Update docs, tests, and CI to make the new layout canonical.

**Tech Stack:** Swift, AppKit, SwiftUI, CoreGraphics, Carbon, Bash, Make, GitHub Actions.

---

### Task 1: Move Files Into the New Layout

**Files:**
- Move: `swift-helper/*.swift` to `Sources/PushToTalk/{App,CLI,Core,Daemon}/`
- Move: `swift-helper/Info.plist` and `swift-helper/AppIcon.icns` to `Sources/PushToTalk/Resources/`
- Move: root scripts to `scripts/`
- Move: `swift-helper/Makefile`, `package-dmg.sh`, and DMG artwork to `packaging/`
- Move: generated binaries and app bundle from `assets/` to `dist/`

- [ ] Create the target directories.
- [ ] Move files with `git mv` so history is preserved.
- [ ] Remove obsolete `.gitkeep`, empty `src`, `swift-helper`, and `assets` directories.

### Task 2: Update Build and Packaging Paths

**Files:**
- Modify: `packaging/Makefile`
- Modify: `packaging/package-dmg.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] Update `packaging/Makefile` so it compiles all Swift files under `Sources/PushToTalk`, embeds resources from `Sources/PushToTalk/Resources`, and writes `dist/pushtotalk` and `dist/PushToTalk.app`.
- [ ] Update `packaging/package-dmg.sh` to call `make -C packaging`, stage `dist/PushToTalk.app`, and use packaging artwork.
- [ ] Update CI to use `make -C packaging`, zip `scripts`, `dist`, and docs, then run `./packaging/package-dmg.sh`.

### Task 3: Update Install and Lifecycle Scripts

**Files:**
- Modify: `scripts/install-app.sh`
- Modify: `scripts/install-daemon.sh`
- Modify: `scripts/restart-daemon.sh`
- Modify: `scripts/uninstall-app.sh`
- Modify: `scripts/uninstall-daemon.sh`

- [ ] Compute `REPO_ROOT` from each script's directory.
- [ ] Replace `swift-helper` build calls with `make -C "$REPO_ROOT/packaging"`.
- [ ] Replace `assets` binary and app paths with `dist`.
- [ ] Update user-facing command hints to reference `./scripts/restart-daemon.sh`.

### Task 4: Refresh Documentation

**Files:**
- Modify: `README.md`
- Create: `docs/architecture.md`
- Create: `docs/installation.md`
- Create: `docs/configuration.md`
- Create: `docs/troubleshooting.md`
- Create: `docs/development.md`

- [ ] Rewrite README as a concise overview with quick start and links.
- [ ] Move implementation details into `docs/architecture.md`.
- [ ] Move install, permission, and uninstall details into `docs/installation.md`.
- [ ] Move JSON config details into `docs/configuration.md`.
- [ ] Move failure diagnosis into `docs/troubleshooting.md`.
- [ ] Move build/test/package commands into `docs/development.md`.

### Task 5: Update Tests

**Files:**
- Rename: `tests/check-swift-only-project.swift` to `tests/check-project-structure.swift`
- Modify: `tests/check-project-structure.swift`
- Modify: `tests/check-daemon-release-flow.swift`

- [ ] Update tests to read Swift files recursively from `Sources/PushToTalk`.
- [ ] Assert old root scripts, `swift-helper`, `assets`, and `src` are gone.
- [ ] Assert new docs and canonical commands are documented.
- [ ] Keep daemon behavior checks pointed at the moved files.

### Task 6: Verify, Commit, Push, PR

**Files:**
- All moved and modified files.

- [ ] Run `swift tests/check-project-structure.swift`.
- [ ] Run `swift tests/check-daemon-release-flow.swift`.
- [ ] Run `make -C packaging`.
- [ ] Run `git status --short` and inspect the diff.
- [ ] Commit with a structure-focused message.
- [ ] Push `codex/restructure-project-layout`.
- [ ] Open a pull request against `main`.
