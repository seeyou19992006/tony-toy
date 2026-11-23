#!/bin/bash

# 安装 dist/build 下的 .app 到 /Applications，并重启应用。
# 结束旧进程 -> ditto 替换 bundle（保留签名与元数据）-> 校验签名 -> 启动。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

source "$REPO_ROOT/scripts/developer-settings.sh"
if [ -f "$REPO_ROOT/scripts/developer-settings.local.sh" ]; then
    source "$REPO_ROOT/scripts/developer-settings.local.sh"
fi

APP_SRC="$REPO_ROOT/$BUILD_DIR/$APP_NAME"
DEST_DIR="/Applications"
DEST_APP="$DEST_DIR/$APP_NAME"
STAGE_APP="$DEST_DIR/.$BINARY_NAME.app.installing"
APP_EXEC="$DEST_APP/Contents/MacOS/$BINARY_NAME"

if [ -z "${APP_NAME:-}" ] || [ -z "${BINARY_NAME:-}" ]; then
    echo "❌ APP_NAME / BINARY_NAME 未配置，中止。"
    exit 1
fi

if [ ! -d "$APP_SRC" ]; then
    echo "❌ 找不到构建产物: $APP_SRC"
    echo "💡 请先执行 just build"
    exit 1
fi

# 1. 结束运行中的旧实例
if pgrep -f "$APP_EXEC" >/dev/null 2>&1; then
    echo "⏹  正在退出运行中的 $CF_BUNDLE_NAME ..."
    pkill -f "$APP_EXEC" 2>/dev/null || true
    for _ in $(seq 1 30); do
        pgrep -f "$APP_EXEC" >/dev/null 2>&1 || break
        sleep 0.2
    done
    if pgrep -f "$APP_EXEC" >/dev/null 2>&1; then
        echo "   ⚠️ 进程未响应，强制结束"
        pkill -9 -f "$APP_EXEC" 2>/dev/null || true
        sleep 0.3
    fi
else
    echo "ℹ️ 当前没有运行中的实例"
fi

# 2. 安装（先落到暂存目录再替换，避免半途失败把应用弄坏）
echo "📥 正在安装到 $DEST_APP ..."
rm -rf "$STAGE_APP"
ditto "$APP_SRC" "$STAGE_APP"
rm -rf "$DEST_APP"
mv "$STAGE_APP" "$DEST_APP"

# 3. 本地构建不带隔离属性，这里只是兜底清一次
xattr -cr "$DEST_APP" 2>/dev/null || true

# 4. 校验签名
if codesign --verify --deep --strict "$DEST_APP" >/dev/null 2>&1; then
    echo "   🔏 签名校验通过"
else
    echo "   ⚠️ 签名校验失败，辅助功能权限可能需要重新授权"
fi

# 5. 启动
echo "🚀 正在启动 $CF_BUNDLE_NAME ..."
open -a "$DEST_APP"

for _ in $(seq 1 25); do
    PIDS="$(pgrep -f "$APP_EXEC" 2>/dev/null | tr '\n' ' ' || true)"
    if [ -n "$PIDS" ]; then
        echo "✅ 已安装并重启: $DEST_APP (PID: $(echo "$PIDS" | xargs))"
        exit 0
    fi
    sleep 0.2
done

echo "⚠️ 未检测到 $CF_BUNDLE_NAME 进程，请检查系统日志或手动启动。"
exit 1
