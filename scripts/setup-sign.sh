#!/bin/bash

set -euo pipefail

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "🔨 正在创建符合 macOS 策略的标准代码签名证书..."
mkdir -p local-sign

# 创建符合苹果标准的完整配置文件
cat > local-sign/openssl.cnf <<EOF
[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
prompt              = no
x509_extensions     = v3_codesign

[ req_distinguished_name ]
CN                  = TonyToy Local Sign

[ v3_codesign ]
basicConstraints    = critical, CA:FALSE
keyUsage            = critical, digitalSignature
extendedKeyUsage    = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# 生成证书 (使用显式配置文件)
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -config local-sign/openssl.cnf \
    -extensions v3_codesign \
    -keyout local-sign/key.pem \
    -out local-sign/cert.pem

# 解决 OpenSSL 3.x 与 macOS security 工具的兼容性问题
if openssl pkcs12 -help 2>&1 | grep -q "\-legacy"; then
    openssl pkcs12 -export -inkey local-sign/key.pem -in local-sign/cert.pem -out local-sign/TonyToyLocalSign.p12 -passout pass:123456 -name "TonyToy Local Sign" -legacy
else
    openssl pkcs12 -export -inkey local-sign/key.pem -in local-sign/cert.pem -out local-sign/TonyToyLocalSign.p12 -passout pass:123456 -name "TonyToy Local Sign"
fi

rm local-sign/openssl.cnf

# 自动探测 login 钥匙串路径
KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"
if [ ! -f "$KEYCHAIN_PATH" ]; then KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain"; fi

# 在导入前强制解锁 login 钥匙串
printf "请输入登录密码以确认导入权限: "
read -rs PASSWORD
echo ""

echo "🔐 正在清理旧证书并重新导入到: $KEYCHAIN_PATH ..."
# 深度清理：先删除所有同名身份
security delete-identity -c "TonyToy Local Sign" "$KEYCHAIN_PATH" 2>/dev/null || true
security delete-certificate -c "TonyToy Local Sign" "$KEYCHAIN_PATH" 2>/dev/null || true
# 同时清理系统钥匙串里的旧证书 (防止干扰)
sudo security delete-certificate -c "TonyToy Local Sign" /Library/Keychains/System.keychain 2>/dev/null || true

# 1. 解锁
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN_PATH"

# 2. 导入 P12 (只导入到 login，这才是签名的正确位置)
security import local-sign/TonyToyLocalSign.p12 -k "$KEYCHAIN_PATH" -P 123456 -T /usr/bin/codesign -T /usr/bin/security -A

# 3. 授权 codesign 工具
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN_PATH" >/dev/null 2>&1

echo "🛡️ 正在将【证书】设为系统信任 (需要 sudo 密码)..."
# 注意：只添加 cert.pem (公钥) 到系统信任，不添加私钥
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain local-sign/cert.pem

echo ""
echo "✅ 证书配置成功！"
echo "--------------------------------------------------"
echo "🔎 现在的有效签名身份状态："
security find-identity -v -p codesigning | grep "TonyToy Local Sign"
