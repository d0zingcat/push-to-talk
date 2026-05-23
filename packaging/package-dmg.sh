#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODESIGN_IDENTITY="${PUSHTOTALK_CODESIGN_IDENTITY:-}"
BUNDLE_ID="com.pushtotalk.PushToTalk"

echo "==> 编译 GUI App..."
make -C "$REPO_ROOT/packaging"

if [ ! -d "$REPO_ROOT/dist/PushToTalk.app" ]; then
    echo "错误: dist/PushToTalk.app 未生成！" >&2
    exit 1
fi

echo "==> 准备 DMG 暂存目录..."
DMG_STAGE="$REPO_ROOT/dist/dmg_stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"

echo "==> 复制 PushToTalk.app 到暂存目录..."
cp -R "$REPO_ROOT/dist/PushToTalk.app" "$DMG_STAGE/"

echo "==> 签名 DMG 内的 PushToTalk.app..."
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$DMG_STAGE/PushToTalk.app"
else
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$DMG_STAGE/PushToTalk.app"
fi

echo "==> 生成美化 DMG 文件..."
mkdir -p "$REPO_ROOT/dist"
rm -f "$REPO_ROOT/dist/PushToTalk.dmg"

if command -v create-dmg &> /dev/null; then
    echo "发现 create-dmg，生成精美安装界面..."
    create-dmg \
      --volname "PushToTalk Installer" \
      --volicon "$REPO_ROOT/Sources/PushToTalk/Resources/AppIcon.icns" \
      --background "$SCRIPT_DIR/dmg_background.tiff" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --icon "PushToTalk.app" 150 185 \
      --hide-extension "PushToTalk.app" \
      --app-drop-link 450 185 \
      "$REPO_ROOT/dist/PushToTalk.dmg" \
      "$DMG_STAGE/"
else
    echo "警告: 未找到 create-dmg，使用 hdiutil 备用打包方式 (无可视化拖拽界面)..."
    ln -s /Applications "$DMG_STAGE/Applications"
    hdiutil create -volname "PushToTalk" -srcfolder "$DMG_STAGE" -ov -format UDZO "$REPO_ROOT/dist/PushToTalk.dmg"
fi

echo "==> 清理暂存目录..."
rm -rf "$DMG_STAGE"

echo "✓ DMG 打包完成: $REPO_ROOT/dist/PushToTalk.dmg"
