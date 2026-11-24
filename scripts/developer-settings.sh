#!/bin/bash

# Shared defaults for local development/build/install.
# Developers can override any value in scripts/developer-settings.local.sh.

APP_NAME="${APP_NAME:-TonyToy.app}"
BINARY_NAME="${BINARY_NAME:-TonyToy}"
CF_BUNDLE_NAME="${CF_BUNDLE_NAME:-TonyToy}"
BUNDLE_ID="${BUNDLE_ID:-com.sxl.tonytoy}"
APP_VERSION="${APP_VERSION:-1.3.1}"
# 构建号：用 git 提交数，每次提交自动递增，无需手工维护。
# 不在 git 仓库里（如从 tarball 构建）时退回 0。
APP_BUILD="${APP_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
MIN_OS_VERSION="${MIN_OS_VERSION:-11.0}"
IS_AGENT_APP="${IS_AGENT_APP:-true}" # Set to true for menu-bar/background apps (LSUIElement)
BUILD_DIR="${BUILD_DIR:-dist/build}"
PACKAGE_DIR="${PACKAGE_DIR:-dist/package}"
DMG_NAME="${DMG_NAME:-${CF_BUNDLE_NAME}-${APP_VERSION}.dmg}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-${CF_BUNDLE_NAME}}"
DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-660}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-360}"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-160}"
DMG_APP_POS_X="${DMG_APP_POS_X:-110}"
DMG_APP_POS_Y="${DMG_APP_POS_Y:-180}"
DMG_APPS_POS_X="${DMG_APPS_POS_X:-330}"
DMG_APPS_POS_Y="${DMG_APPS_POS_Y:-180}"
DMG_README_POS_X="${DMG_README_POS_X:-550}"
DMG_README_POS_Y="${DMG_README_POS_Y:-180}"

# Can be empty to skip code signing in local experiments.
SIGN_IDENTITY="${SIGN_IDENTITY:-TonyToy Local Sign}"
# Optional dedicated keychain for SSH/CI signing, e.g. ~/Library/Keychains/tonytoy-signing.keychain-db
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"
