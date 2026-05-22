#!/usr/bin/env bash
set -euo pipefail

TARGET_IME="${1:-豆包输入法}"
BINARY_DIR="$HOME/.local/bin"
BINARY="$BINARY_DIR/pushtotalk"
PLIST_LABEL="com.pushtotalk.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODESIGN_IDENTITY="${PUSHTOTALK_CODESIGN_IDENTITY:-}"

echo "==> 编译 Swift helper..."
make -C "$SCRIPT_DIR/swift-helper"

echo "==> 安装二进制到 $BINARY..."
mkdir -p "$BINARY_DIR"
cp "$SCRIPT_DIR/assets/pushtotalk" "$BINARY"
chmod +x "$BINARY"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    echo "==> 使用代码签名身份签名: $CODESIGN_IDENTITY"
    codesign --force --sign "$CODESIGN_IDENTITY" "$BINARY"
else
    echo "==> 未设置 PUSHTOTALK_CODESIGN_IDENTITY，跳过代码签名。"
fi

echo "==> 写入 LaunchAgent: $PLIST_PATH"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
        <string>daemon</string>
        <string>--target</string>
        <string>$TARGET_IME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>StandardOutPath</key>
    <string>/tmp/pushtotalk-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/pushtotalk-daemon.err</string>
</dict>
</plist>
EOF

echo "==> 加载 LaunchAgent..."
# 如果已加载先卸载
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo "✓ 安装完成！"
echo "  按住右 Command 说话，松开停止，3 秒后自动恢复原输入法。"
echo ""
echo "  日志：tail -f /tmp/pushtotalk-daemon.log"
echo "  错误：tail -f /tmp/pushtotalk-daemon.err"
echo ""
echo "  如果语音没有触发，请在「系统设置 → 隐私与安全性 → 辅助功能」授权：$BINARY"
echo "  授权后只需运行 ./restart-daemon.sh，不要再次安装，否则 macOS 可能要求重新授权。"
