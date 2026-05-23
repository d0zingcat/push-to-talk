# Configuration

PushToTalk reads optional configuration from:

```text
~/.config/pushtotalk/config.json
```

Example with default values:

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
  "option_press_delay": 0.3,
  "listening_mode": "double_tap_option"
}
```

## Parameters

- `target_ime`: Target voice input method name.
- `trigger_keycode`: Virtual key code to hold for push-to-talk. Default `54` is right Command.
- `trigger_flag_raw`: Device raw flag mask for the trigger key. Default `16` is right Command.
- `simulate_keycode`: Virtual key code to simulate. Default `61` is right Option.
- `simulate_flag_raw`: Device raw flag mask for the simulated key. Default `64` is right Option.
- `restore_delay`: Seconds to wait before restoring the previous input source.
- `settle_delay`: Seconds to wait after switching input sources before triggering voice input.
- `option_tap_interval`: Seconds between simulated Option taps.
- `option_press_delay`: Seconds the trigger key must be held before activation.
- `listening_mode`: `double_tap_option` or `long_press_fn`.

Restart the daemon after editing configuration:

```bash
./scripts/restart-daemon.sh
```
