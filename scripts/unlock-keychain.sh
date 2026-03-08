#!/bin/bash

# 禁用回显获取密码
printf "请输入登录密码以解锁 Keychain: "
read -rs PASSWORD
echo ""

if [ -z "$PASSWORD" ]; then
    echo "❌ 密码不能为空。"
    exit 1
fi

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# 兼容旧版 macOS 路径
if [ ! -f "$KEYCHAIN" ]; then
    KEYCHAIN="$HOME/Library/Keychains/login.keychain"
fi

echo "🔐 正在解锁: $KEYCHAIN ..."

# 执行解锁
if ! security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" 2>/dev/null; then
    echo "❌ 密码错误或无法解锁 Keychain。"
    exit 1
fi

# 授权 codesign 工具 (这是解决 errSecInternalComponent 的关键)
echo "🛡️ 正在授权 codesign 工具..."
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "⚠️ 授权执行中，如果之后签名仍报错，请确认密码正确。"
fi

echo "✅ Keychain 已解锁并授权成功。"
