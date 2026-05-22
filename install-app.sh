#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODESIGN_IDENTITY="${PUSHTOTALK_CODESIGN_IDENTITY:-}"

echo "==> 编译并打包 GUI App..."
make -C "$SCRIPT_DIR/swift-helper"

# 检查目标安装目录
INSTALL_DIR="/Applications"
if [[ ! -w "$INSTALL_DIR" ]]; then
    INSTALL_DIR="$HOME/Applications"
    echo "==> /Applications 不可写，切换到用户目录: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi
APP_DEST="$INSTALL_DIR/PushToTalk.app"

echo "==> 卸载冲突的 LaunchAgent 守护进程..."
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.pushtotalk.daemon.plist"
if [[ -f "$LEGACY_PLIST" ]]; then
    launchctl unload "$LEGACY_PLIST" 2>/dev/null || true
    rm -f "$LEGACY_PLIST"
    echo "  已停止并删除旧版命令行守护进程: $LEGACY_PLIST"
fi

echo "==> 停止可能正在运行的 GUI 实例..."
osascript -e 'tell application "PushToTalk" to quit' 2>/dev/null || true
sleep 1

echo "==> 安装 PushToTalk.app 到 $INSTALL_DIR..."
rm -rf "$APP_DEST"
cp -R "$SCRIPT_DIR/assets/PushToTalk.app" "$APP_DEST"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    echo "==> 使用代码签名身份对 App 进行深层签名: $CODESIGN_IDENTITY"
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DEST"
else
    echo "==> 未设置 PUSHTOTALK_CODESIGN_IDENTITY，默认使用本地 Ad-hoc 签名 (-)..."
    codesign --force --deep --sign - "$APP_DEST"
fi

echo "==> 重置 macOS 辅助功能 (Accessibility) 权限缓存，以避免由于二进制或签名改变导致的系统缓存失效..."
tccutil reset Accessibility com.pushtotalk.PushToTalk || true

echo "==> 启动 PushToTalk App..."
open "$APP_DEST"

echo ""
echo "✓ 安装完成并已成功启动！"
echo "  你会在菜单栏右上角看到一个麦克风/波形图标。"
echo ""
echo "  重要提示："
echo "  1. 首次打开如果提示权限，请按引导在「系统设置 → 隐私与安全性 → 辅助功能」授权：PushToTalk.app"
echo "  2. 如果重新编译过，macOS 可能会使之前的权限失效，你可以通过重新签名或者在系统设置中删除后再重新添加授权来解决。"
echo ""
