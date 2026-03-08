#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

source "$REPO_ROOT/scripts/developer-settings.sh"
if [ -f "$REPO_ROOT/scripts/developer-settings.local.sh" ]; then
    source "$REPO_ROOT/scripts/developer-settings.local.sh"
fi

APP_PATH="$REPO_ROOT/$BUILD_DIR/$APP_NAME"
PACKAGE_DIR_PATH="$REPO_ROOT/$PACKAGE_DIR"
DMG_PATH="$PACKAGE_DIR_PATH/$DMG_NAME"
STAGE_DIR="$PACKAGE_DIR_PATH/.dmg-stage"
TEMP_DMG_PATH="$PACKAGE_DIR_PATH/.tmp-$DMG_NAME"
DMG_LAYOUT_TEMPLATE="$REPO_ROOT/scripts/dmg-layout/layout.dsstore"

# Optional override: TONYTOY_CODESIGN_IDENTITY
if [ "${TONYTOY_CODESIGN_IDENTITY+x}" = "x" ]; then
    SIGN_IDENTITY="$TONYTOY_CODESIGN_IDENTITY"
fi

echo "📦 开始打包 DMG: $DMG_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 找不到构建产物: $APP_PATH"
    echo "💡 请先执行 ./scripts/build.sh"
    exit 1
fi

cleanup() {
    rm -rf "$STAGE_DIR"
    rm -f "$TEMP_DMG_PATH"
}
trap cleanup EXIT

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$PACKAGE_DIR_PATH"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

# Add instructions for self-signed app
cat > "$STAGE_DIR/README-Install.txt" <<EOF
TonyToy 快速安装指南 (macOS)
---------------------------------
由于此应用使用自签名证书，请按照以下步骤完成安装：

1. 将 TonyToy.app 拖入“应用程序” (Applications) 文件夹。
2. ⚠️ 第一次运行前，请打开“终端” (Terminal.app)，复制并运行以下命令：

   sudo xattr -cr /Applications/TonyToy.app

   (运行后可能需要输入您的开机密码)

3. 现在您可以直接从“启动台”或“应用程序”文件夹正常启动 TonyToy 了。

💡 常见问题：
- 权限失效：如果更新后功能失效（且系统设置已勾选“辅助功能”），请在“系统设置 -> 隐私与安全性 -> 辅助功能”中，先【取消勾选】TonyToy，然后再【重新勾选】。
- 彻底重置：如果权限依然无效，可以在终端运行以下命令强制重置权限数据库：
  tccutil reset Accessibility $BUNDLE_ID

💡 为什么需要这一步？
macOS 对非 App Store 下载的应用会有安全限制。运行上述命令将告知系统此应用是安全的，从而绕过“无法验证开发者”的提示。
EOF


# 💡 核心优化：在打包前直接应用布局模板，避免挂载冲突
if [ -f "$DMG_LAYOUT_TEMPLATE" ]; then
    echo "🪄 正在将布局模板应用到暂存区..."
    cp "$DMG_LAYOUT_TEMPLATE" "$STAGE_DIR/.DS_Store"
else
    echo "ℹ️ 未找到布局模板，将使用系统默认布局。"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "🔏 正在执行自签名: $SIGN_IDENTITY"
    # Ensure keychain is refreshed for SSH
    security list-keychains -d user -s login.keychain-db $(security list-keychains -d user | tr -d '"') 2>/dev/null || true
    
    CODESIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY")
    if [ -n "${SIGN_KEYCHAIN:-}" ]; then
        CODESIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
    fi
    CODESIGN_ARGS+=("$STAGE_DIR/$APP_NAME")

    if ! codesign "${CODESIGN_ARGS[@]}"; then
        echo "❌ 签名失败。SSH 环境请先运行 'just unlock'。"
        exit 1
    fi

    echo "🔍 验证签名状态..."
    codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/$APP_NAME"
fi

echo "🚀 正在生成最终镜像..."
rm -f "$TEMP_DMG_PATH" "$DMG_PATH"

# 直接生成压缩后的最终 DMG，不经过中间挂载步骤
if ! hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null; then
    echo "❌ 生成 DMG 失败。"
    exit 1
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "🔏 正在签名最终 DMG..."
    FINAL_CODESIGN_ARGS=(--sign "$SIGN_IDENTITY")
    if [ -n "${SIGN_KEYCHAIN:-}" ]; then
        FINAL_CODESIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
    fi
    FINAL_CODESIGN_ARGS+=("$DMG_PATH")
    codesign "${FINAL_CODESIGN_ARGS[@]}"
fi

echo "✅ 打包成功:"
echo "   - DMG: $DMG_PATH"
