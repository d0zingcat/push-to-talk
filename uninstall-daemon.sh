#!/usr/bin/env bash
set -euo pipefail

PLIST_LABEL="com.pushtotalk.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
BINARY="$HOME/.local/bin/pushtotalk"

echo "==> 停止并卸载 LaunchAgent..."
launchctl unload "$PLIST_PATH" 2>/dev/null && echo "  已停止" || echo "  (未在运行)"
rm -f "$PLIST_PATH" && echo "  已删除 $PLIST_PATH"

echo "==> 删除二进制..."
rm -f "$BINARY" && echo "  已删除 $BINARY"

echo ""
echo "✓ 卸载完成。"
