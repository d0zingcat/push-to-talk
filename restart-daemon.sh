#!/usr/bin/env bash
set -euo pipefail

PLIST_LABEL="com.pushtotalk.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
LOG_DIR="$HOME/Library/Logs/pushtotalk"

if [[ ! -f "$PLIST_PATH" ]]; then
    echo "Error: LaunchAgent plist not found: $PLIST_PATH" >&2
    echo "Run ./install-daemon.sh first." >&2
    exit 1
fi

echo "==> 重启 LaunchAgent..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo "✓ 已重启。"
echo "  日志：tail -f $LOG_DIR/pushtotalk-daemon.log"
echo "  错误：tail -f $LOG_DIR/pushtotalk-daemon.err"
