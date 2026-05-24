# Right‑Command → Fn Long‑Press Passthrough — Investigation Notes

This document records what we tried, what works, and the bug that is currently
blocking us in the experimental "hold Right Command → simulate Fn long‑press"
path. It is meant to give the next session (or a different reviewer) enough
context to pick up without re‑deriving everything.

Status: **partially working, blocked on macOS HID modifier‑state desync.**

---

## Goal

WeChat's voice‑input shortcut is a **Fn long‑press** (hold Fn for ~300 ms,
release to send). Our daemon already supports a "Right Option double‑tap"
trigger for Doubao, but for WeChat we need a true Fn long‑press.

The user‑facing model we want:

> Hold Right Command → daemon switches IME → simulates Fn DOWN. Release Right
> Command → daemon simulates Fn UP → WeChat accepts the recording.

Right Cmd is the trigger because it's an ergonomic key that the user doesn't
otherwise use; the daemon swallows it and substitutes Fn.

---

## What we have confirmed works

### 1. HID‑level Fn long‑press triggers WeChat

`tests/hold-fn.swift` is a minimal standalone driver:

- Builds the event with `CGEventSource(stateID: .hidSystemState)`
- Posts to `.cghidEventTap`
- Holds for a configurable duration, then posts the Fn UP

Run it, focus WeChat, and the voice popup appears reliably. This proved the
fundamental technique. The corresponding README section (`Key simulation and
the HID state requirement`) has the rationale: IMEs poll
`CGEventSourceKeyState(.hidSystemState, …)` mid‑long‑press, and only the HID
event tap actually updates that state.

### 2. The daemon's `long_press_fn` listening mode

`swift-helper/DaemonController.swift` already wires a `long_press_fn` mode
into the existing Right‑Cmd handler:

- `daemonOnRightCmdDown` schedules `daemonActivateVoiceSession`
- That switches IME, then calls `simulateFnDown()` (HID layer)
- `daemonOnRightCmdUp` calls `simulateFnUp()` and restores IME

This path works as long as the *physical* Right Cmd events arrive cleanly,
which is what the experimental harness below exists to validate.

### 3. The 0.45 s phantom‑Cmd‑DOWN suppress window

`DaemonState.swift:28` defines
`DAEMON_RIGHT_CMD_RELEASE_SUPPRESS_INTERVAL = 0.45`, and
`DaemonController.swift:160-163` ignores any Right‑Cmd DOWN event that lands
inside that window after a release. We added this because macOS regularly
fires a synthetic Cmd DOWN shortly after a real release if the modifier state
has been touched by an injected event during the press. **Without this guard
the daemon would re‑enter the press handler immediately and start a second
voice session.** This is the same family of state‑sync quirk that's biting the
new test (see below).

---

## What we are stuck on

### Symptom

Running `tests/rcmd-to-fn.swift` (the experimental "translate Right Cmd to Fn
long‑press" harness):

```
right-Cmd down, waiting 300ms...
→ right-Cmd UP (HID suppress) at 2026-05-23 16:32:51 +0000
→ Fn DOWN at 2026-05-23 16:32:51 +0000
→ Fn UP at 2026-05-23 16:32:58 +0000      ← only appears on the 2nd press
```

Real behavior:

1. Press 1 → Fn DOWN fires correctly (300 ms after press).
2. Release 1 → **nothing logs**. `isCmdDown` stays `true`. WeChat still sees Fn held.
3. Press 2 → at some point during this cycle the `Fn UP` line appears, but the cycle is now mis‑aligned.
4. Press 3 → only now does a fresh Fn long‑press actually fire in WeChat.

Net effect: voice input requires three physical Right‑Cmd presses to fire
once.

### Why this happens (working hypothesis)

The harness deliberately injects a synthetic **Right‑Cmd UP** at the HID layer
while the user is still physically holding the key. The injection is necessary
because WeChat refuses to fire on the Fn+Cmd modifier combo — clearing Cmd
from the HID state makes WeChat see a clean Fn long‑press.

The cost: three different state trackers in macOS now disagree.

| Tracker | Right Cmd state |
|---|---|
| HID / kernel (physical) | Down (key is still pressed) |
| Event‑system modifier flags | Up (because of our injection) |
| Our `isCmdDown` Swift var | True |

When the user physically releases, the kernel sees its event‑system flag was
*already* "up" and so either:

- emits no `flagsChanged` at all, or
- emits one whose `flag` or `pid` doesn't match the `else if !isDown,
  isCmdDown` branch in `tapCallback`.

Either way our release branch never runs, `isCmdDown` is never cleared, and
the next physical event we *do* see gets attributed to the wrong half of the
cycle. The production daemon's 0.45 s phantom‑DOWN window is the inverse of
the same problem.

### Evidence still missing

We have not yet captured the full per‑event log to confirm which of those
sub‑cases is happening. The harness has a diagnostic line that prints every
`flagsChanged` event with its keycode / pid / flags, but the binary in the
user's last test run was compiled before that line was added, so the log we
have only shows the high‑level prints. **Next session should rebuild the
harness and capture a one‑press‑release cycle's full event stream** — see
"Next steps".

---

## Files in this experiment

```
tests/
  hold-fn.swift         standalone Fn long‑press driver (CONFIRMED WORKING)
  rcmd-to-fn.swift      Right‑Cmd → Fn translator harness (BUGGY, see above)
docs/
  right-cmd-to-fn-investigation.md   (this file)
```

Both test binaries (`assets/hold-fn`, `assets/rcmd-to-fn`) are now
gitignored — rebuild locally before each run.

Build:

```bash
swiftc -O tests/hold-fn.swift     -o assets/hold-fn
swiftc -O tests/rcmd-to-fn.swift  -o assets/rcmd-to-fn
```

Both binaries need **Accessibility** and **Input Monitoring** permission, and
the production PushToTalk daemon must be stopped while the harness runs
(otherwise both fight over Right Cmd).

---

## Next steps

1. **Capture full event stream.** Rebuild `assets/rcmd-to-fn`, do exactly one
   press → 1 s hold → release → 2 s pause → press → release. Paste the entire
   stderr stream (including every `  flagsChanged: keycode=… pid=… flags=0x…`
   diagnostic line) into the next session. That will tell us definitively
   whether the missing release event is:
   - never fired,
   - fired with `pid != 0` (kernel‑synthesized), or
   - fired with unexpected `flag` bits.

2. **Replace event‑driven release detection with HID polling.** Strongest
   candidate fix: after we inject `Cmd UP + Fn DOWN`, start a 20 ms
   `DispatchSourceTimer` that calls
   `CGEventSource.keyState(for: .hidSystemState, key: 54)`. When that returns
   `false`, fire `Fn UP` and reset state. The HID physical‑state poll is not
   fooled by our own injection — it answers "is the key currently pressed
   down on the hardware".

3. **Promote single bool to a proper state machine.** Replace `isCmdDown:
   Bool` with `enum State { idle, waitingForLongPress, fnHeld }`. The current
   `if isDown, !isCmdDown / else if !isDown, isCmdDown` pair has a third case
   (`isDown && isCmdDown`) that silently drops events — which is exactly the
   gap a re‑fired DOWN can fall into.

4. **Decide whether to keep the HID Cmd UP injection at all.** If WeChat
   would accept Fn+Cmd on some other code path (different `CGEventSource`
   stateID, different `post(tap:)` level, separate Cmd‑clearing strategy via
   `event.flags = .maskSecondaryFn` only on a fresh source), we can avoid
   touching modifier state entirely and the whole class of bug goes away.
   Worth a 30‑minute spike before committing to the polling workaround.

5. **Once the harness is reliable, port the fix back into the daemon.** The
   production `daemonEventCallback` shares the same modifier‑flag‑based
   release detection. If the harness needs polling, the daemon does too
   (it's just luckier because of the 0.45 s phantom suppress window
   masking the symptom).

---

## Production daemon recompile (separate, unstaged)

`assets/pushtotalk` and `assets/PushToTalk.app/Contents/MacOS/PushToTalk` show
up as modified in `git status` from an unrelated rebuild during this session.
**They are not committed as part of this investigation.** Decide separately
whether to ship them.
