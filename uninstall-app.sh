#!/usr/bin/env bash
set -euo pipefail

echo "==> 停止可能正在运行的 PushToTalk App..."
osascript -e 'tell application "PushToTalk" to quit' 2>/dev/null || true
sleep 1
pkill -f "PushToTalk.app/Contents/MacOS/PushToTalk" 2>/dev/null || true

echo "==> 删除开机启动 LaunchAgent..."
GUI_PLIST="$HOME/Library/LaunchAgents/com.pushtotalk.gui.plist"
if [[ -f "$GUI_PLIST" ]]; then
    launchctl unload "$GUI_PLIST" 2>/dev/null || true
    rm -f "$GUI_PLIST"
    echo "  已删除: $GUI_PLIST"
fi

echo "==> 卸载 PushToTalk.app..."
rm -rf "/Applications/PushToTalk.app"
rm -rf "$HOME/Applications/PushToTalk.app"
echo "==> 清除 macOS 辅助功能 (Accessibility) 权限缓存..."
tccutil reset Accessibility com.pushtotalk.PushToTalk || true

echo ""
echo "✓ 卸载完成。"
echo ""
