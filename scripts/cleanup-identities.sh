#!/bin/bash

# 获取 login 钥匙串路径
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if [ ! -f "$KEYCHAIN" ]; then KEYCHAIN="$HOME/Library/Keychains/login.keychain"; fi

NAME="TonyToy Local Sign"
echo "🧹 正在清理名为 '$NAME' 的重复证书..."

COUNT=0
# 循环删除，直到 security 报错找不到该证书为止
while security delete-certificate -c "$NAME" "$KEYCHAIN" 2>/dev/null; do
    COUNT=$((COUNT + 1))
    printf "\r已删除: $COUNT 个"
done

echo ""
echo "✅ 清理完成！共删除了 $COUNT 个重复证书。"

# 顺便修复一下你混乱的 Keychain 搜索列表
echo "🔧 正在重置 Keychain 搜索列表..."
security list-keychains -d user -s "$KEYCHAIN" "/Library/Keychains/System.keychain"

echo "🔎 当前剩余有效身份数量："
security find-identity -v -p codesigning | tail -n 1
