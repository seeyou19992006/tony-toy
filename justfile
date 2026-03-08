# TonyToy Project Management
set shell := ["bash", "-uc"]

scripts := "scripts/"

default:
    @just --list

# 🚀 完整发布全流程 (编译 + 签名打包)
release: build package
    @echo "✨ Release completed successfully!"

# 🏗️ 编译 Apple Silicon 版 .app
build:
    @{{scripts}}build.sh

# 📦 签名并打包为 .dmg
package:
    @{{scripts}}package.sh

# 🔐 解锁 Keychain (SSH 签名必备)
unlock:
    @{{scripts}}unlock-keychain.sh

# 🔑 一键配置自签名证书
setup-sign:
    @{{scripts}}setup-sign.sh

# 🧹 清理构建产物
clean:
    rm -rf dist/

# 🧪 运行所有单元测试
test:
    @tests/run_all.sh

# ⚙️ 初始化本地配置
setup-config:
    @cp {{scripts}}developer-settings.local.example.sh {{scripts}}developer-settings.local.sh || true
