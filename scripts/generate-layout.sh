#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/scripts/developer-settings.sh"
if [ -f "$REPO_ROOT/scripts/developer-settings.local.sh" ]; then
    source "$REPO_ROOT/scripts/developer-settings.local.sh"
fi

TEMPLATE_DIR="$REPO_ROOT/scripts/dmg-layout"
TEMPLATE_FILE="$TEMPLATE_DIR/layout.dsstore"
TEMP_DIR="/tmp/tonytoy-layout-gen"
TEMP_DMG="$TEMP_DIR/temp.dmg"
VOL_NAME="LayoutGenerator"

echo "🎨 正在启动一次性布局生成器..."
mkdir -p "$TEMPLATE_DIR" "$TEMP_DIR"

# 1. 创建一个包含占位文件的临时镜像
echo "📦 创建临时环境..."
mkdir -p "$TEMP_DIR/stage"
touch "$TEMP_DIR/stage/$APP_NAME"
ln -s /Applications "$TEMP_DIR/stage/Applications"
touch "$TEMP_DIR/stage/README-Install.txt"

hdiutil create -volname "$VOL_NAME" -srcfolder "$TEMP_DIR/stage" -ov -format UDRW "$TEMP_DMG" >/dev/null

# 2. 挂载
echo "📂 挂载镜像..."
MOUNT_POINT="$(hdiutil attach "$TEMP_DMG" -nobrowse | awk '/\/Volumes\// {print $3; exit}')"
sleep 2

# 3. 通过 AppleScript 设置布局 (这是唯一生成 .DS_Store 的方法)
echo "🪄 正在配置 Finder 窗口 (可能需要几秒钟)..."
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {120, 120, 120 + $DMG_WINDOW_WIDTH, 120 + $DMG_WINDOW_HEIGHT}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to $DMG_ICON_SIZE
        set position of item "$APP_NAME" of container window to {$DMG_APP_POS_X, $DMG_APP_POS_Y}
        set position of item "Applications" of container window to {$DMG_APPS_POS_X, $DMG_APPS_POS_Y}
        set position of item "README-Install.txt" of container window to {$DMG_README_POS_X, $DMG_README_POS_Y}
        update without registering applications
        delay 3
        close
    end tell
end tell
EOF

# 4. 捕获生成的 .DS_Store
echo "📸 正在捕获布局模板..."
sync
sleep 2
if [ -f "$MOUNT_POINT/.DS_Store" ]; then
    cp "$MOUNT_POINT/.DS_Store" "$TEMPLATE_FILE"
    echo "✅ 成功！模板已保存至: $TEMPLATE_FILE"
else
    echo "❌ 失败：未能生成 .DS_Store 文件。请确保你是在有 GUI 登录的会话中（即使是 SSH，也需要有活跃的图形会话）。"
fi

# 5. 清理
echo "🧹 清理临时文件..."
hdiutil detach "$MOUNT_POINT" -force -quiet
rm -rf "$TEMP_DIR"

echo "🎉 完成。现在你可以直接运行 'just release'，它会自动使用这个模板。"
