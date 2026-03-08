#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use dynamic home directory
DEFAULT_KEYCHAIN="$HOME/Library/Keychains/tonytoy-signing.keychain-db"
SIGN_KEYCHAIN_PATH="${SIGN_KEYCHAIN_PATH:-$DEFAULT_KEYCHAIN}"
SIGN_KEYCHAIN_PASSWORD="${SIGN_KEYCHAIN_PASSWORD:-}"
SIGN_P12_PATH="${SIGN_P12_PATH:-$REPO_ROOT/local-sign/TonyToyLocalSign.p12}"
SIGN_P12_PASSWORD="${SIGN_P12_PASSWORD:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-TonyToy Local Sign}"

if [ -z "$SIGN_KEYCHAIN_PASSWORD" ]; then
    echo "❌ 缺少 SIGN_KEYCHAIN_PASSWORD"
    exit 1
fi

if [ ! -f "$SIGN_P12_PATH" ]; then
    echo "❌ 找不到 p12 文件: $SIGN_P12_PATH"
    exit 1
fi

if ! security list-keychains | grep -Fq "$SIGN_KEYCHAIN_PATH"; then
    current_keychains="$(security list-keychains -d user | tr -d '"')"
    security list-keychains -d user -s "$SIGN_KEYCHAIN_PATH" $current_keychains
fi

if [ ! -f "$SIGN_KEYCHAIN_PATH" ]; then
    security create-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN_PATH"
fi

security set-keychain-settings -lut 21600 "$SIGN_KEYCHAIN_PATH"
security unlock-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN_PATH"

security import "$SIGN_P12_PATH" \
    -k "$SIGN_KEYCHAIN_PATH" \
    -P "$SIGN_P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$SIGN_KEYCHAIN_PASSWORD" \
    "$SIGN_KEYCHAIN_PATH"

echo "✅ SSH/CI 签名 keychain 准备完成"
echo "   - keychain: $SIGN_KEYCHAIN_PATH"
echo "   - identity: $SIGN_IDENTITY"
echo "🔎 可用签名身份："
security find-identity -v -p codesigning "$SIGN_KEYCHAIN_PATH"
