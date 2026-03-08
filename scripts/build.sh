#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

source "$REPO_ROOT/scripts/developer-settings.sh"
if [ -f "$REPO_ROOT/scripts/developer-settings.local.sh" ]; then
    source "$REPO_ROOT/scripts/developer-settings.local.sh"
fi

DIST_DIR="./dist"
BUILD_DIR="$DIST_DIR/build"
SRC_DIR="./src"
RESOURCES_DIR="./resources"
APP_DIR="$BUILD_DIR/$APP_NAME"
APP_CONTENTS_DIR="$APP_DIR/Contents"
APP_MACOS_DIR="$APP_CONTENTS_DIR/MacOS"
APP_RESOURCES_DIR="$APP_CONTENTS_DIR/Resources"
OUTPUT_BINARY="$APP_MACOS_DIR/$BINARY_NAME"
# Build for Apple Silicon (arm64) using target triple
SWIFT_FLAGS=(-O -whole-module-optimization -target arm64-apple-macosx11.0)
LINK_FLAGS=(-framework Cocoa -framework CoreAudio)
SOURCE_FILES_ARRAY=()

collect_source_files() {
    local source_file
    SOURCE_FILES_ARRAY=()

    while IFS= read -r source_file; do
        SOURCE_FILES_ARRAY+=("$source_file")
    done < <(find "$SRC_DIR" -type f -name '*.swift' | LC_ALL=C sort)

    if [ "${#SOURCE_FILES_ARRAY[@]}" -eq 0 ]; then
        echo "❌ 未找到可编译的 Swift 源码文件（$SRC_DIR/*.swift）"
        exit 1
    fi
}

write_info_plist() {
    cat > "$APP_CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BINARY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$CF_BUNDLE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_OS_VERSION</string>
    <key>LSUIElement</key>
    <$IS_AGENT_APP/>
</dict>
</plist>
EOF
}

echo "🔨 正在构建 $APP_NAME (Apple Silicon)..."


if [ ! -d "$RESOURCES_DIR" ]; then
    echo "❌ 找不到资源目录: $RESOURCES_DIR"
    exit 1
fi

if [ ! -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    echo "⚠️ 缺少 $RESOURCES_DIR/AppIcon.icns，应用图标可能显示异常。"
fi

collect_source_files

rm -rf "$APP_DIR"
mkdir -p "$APP_MACOS_DIR" "$APP_RESOURCES_DIR"

echo "   🚀 正在编译源码文件 [${#SOURCE_FILES_ARRAY[@]} 个文件]..."
if ! swiftc "${SWIFT_FLAGS[@]}" "${SOURCE_FILES_ARRAY[@]}" -o "$OUTPUT_BINARY" "${LINK_FLAGS[@]}"; then
    echo "❌ 编译失败。"
    exit 1
fi
chmod +x "$OUTPUT_BINARY"

echo "   📦 正在复制资源并生成配置..."
rsync -a --delete "$RESOURCES_DIR"/ "$APP_RESOURCES_DIR"/
write_info_plist

# Verify architectures
ARCHS=$(lipo -archs "$OUTPUT_BINARY")
echo "✅ 构建成功:"
echo "   - App: $APP_DIR"
echo "   - Architectures: $ARCHS"

# 创建二进制文件的便捷软链接到 dist 目录
BINARY_SYMLINK="$DIST_DIR/$BINARY_NAME"
rm -f "$BINARY_SYMLINK"
ln -s "build/$APP_NAME/Contents/MacOS/$BINARY_NAME" "$BINARY_SYMLINK"
echo "   - 快捷运行: $BINARY_SYMLINK"

