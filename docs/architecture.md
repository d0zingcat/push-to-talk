# Architecture

PushToTalk is a Swift-only macOS utility with two operating modes:

- A menu bar GUI app for everyday use.
- A background LaunchAgent daemon for users who prefer no GUI.

Both modes share the same input-source switching and key-event simulation code.

## Source Layout

```text
Sources/PushToTalk/
├── App/        # NSStatusItem, NSPopover, SwiftUI menu, app state
├── CLI/        # command-line argument parsing
├── Core/       # configuration, input sources, permissions, logging, key events
├── Daemon/     # event tap state and push-to-talk session flow
├── Resources/  # Info.plist and AppIcon.icns
└── main.swift  # GUI or CLI entrypoint
```

## Voice Session Flow

```text
Right Command down
  -> wait option_press_delay to avoid accidental taps
  -> save current input source
  -> select target voice input method
  -> wait settle_delay
  -> trigger voice input

Right Command up
  -> stop long-press trigger if needed
  -> wait restore_delay
  -> restore previous input source
```

If the user starts typing during the restore delay, PushToTalk restores the previous input source immediately.

## macOS APIs

- `CGEventTap` observes global `flagsChanged` and `keyDown` events in listen-only mode.
- `TISCopyCurrentKeyboardInputSource` reads the active input source.
- `TISSelectInputSource` switches to Doubao or another configured input method.
- `CGEvent` posts synthetic Option or Fn trigger events.

## Stability Guards

- The event tap is listen-only, so it cannot consume right Command.
- Short right Command taps are ignored until the activation delay passes.
- Trigger events are posted only after the input source settles.
- If the target IME cannot be selected, no synthetic trigger events are posted.
- If macOS repeatedly disables the event tap, the daemon exits with code 70.
