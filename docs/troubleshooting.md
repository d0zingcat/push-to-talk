# Troubleshooting

## Voice Input Does Not Start

Check daemon logs:

```bash
cat ~/Library/Logs/pushtotalk/pushtotalk-daemon.err
tail -f ~/Library/Logs/pushtotalk/pushtotalk-daemon.log
```

If Accessibility permission is missing, grant it to `~/.local/bin/pushtotalk` or `PushToTalk.app`, depending on which mode you use.

If logs show right Command events and `posted right-option tap` but Doubao does not open voice input, re-check Accessibility permission. macOS may allow event observation while still blocking synthetic events.

## Target IME Is Not Found

List input source names:

```bash
dist/pushtotalk list-sources
```

Then install with the exact localized name:

```bash
./scripts/install-daemon.sh "<exact name>"
```

## IME Restores Too Early

Increase `restore_delay` in `~/.config/pushtotalk/config.json`, then restart:

```bash
./scripts/restart-daemon.sh
```

## Event Tap Is Disabled Repeatedly

If logs show repeated tap disable events and exit code 70, check for system-wide input lag, permission changes, or conflicting input utilities, then restart:

```bash
./scripts/restart-daemon.sh
```
