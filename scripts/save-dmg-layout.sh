#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/scripts/developer-settings.sh"
if [ -f "$REPO_ROOT/scripts/developer-settings.local.sh" ]; then
  source "$REPO_ROOT/scripts/developer-settings.local.sh"
fi

DMG_PATH="${1:-$REPO_ROOT/$PACKAGE_DIR/$DMG_NAME}"
OUTPUT_PATH="$REPO_ROOT/scripts/dmg-layout/layout.dsstore"
MOUNT_POINT=""

cleanup() {
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
}
trap cleanup EXIT

if [ ! -f "$DMG_PATH" ]; then
  echo "❌ 找不到 DMG: $DMG_PATH"
  exit 1
fi

MOUNT_POINT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly | awk '/\/Volumes\// {print $3; exit}')"
if [ -z "$MOUNT_POINT" ]; then
  echo "❌ 挂载 DMG 失败: $DMG_PATH"
  exit 1
fi

if [ ! -f "$MOUNT_POINT/.DS_Store" ]; then
  echo "❌ DMG 中没有 .DS_Store，先手动调整一次 Finder 布局再保存。"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
cp "$MOUNT_POINT/.DS_Store" "$OUTPUT_PATH"

echo "✅ 已保存布局模板: $OUTPUT_PATH"
