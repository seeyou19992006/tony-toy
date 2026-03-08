#!/bin/bash

# Copy this file to scripts/developer-settings.local.sh and customize values.
# That local file is gitignored and only applies on your machine.

APP_NAME="TonyToy.app"
BINARY_NAME="TonyToy"
CF_BUNDLE_NAME="TonyToy"
BUNDLE_ID="com.sxl.tonytoy"
APP_VERSION="2.0"
BUILD_DIR="dist/build"
PACKAGE_DIR="dist/package"
DMG_NAME="TonyToy-2.0.dmg"
DMG_VOLUME_NAME="TonyToy"
DMG_WINDOW_WIDTH="560"
DMG_WINDOW_HEIGHT="360"
DMG_ICON_SIZE="128"
DMG_APP_POS_X="170"
DMG_APP_POS_Y="170"
DMG_APPS_POS_X="390"
DMG_APPS_POS_Y="170"
SIGN_IDENTITY="TonyToy Local Sign"
# Optional dedicated keychain for SSH/CI signing.
# SIGN_KEYCHAIN="$HOME/Library/Keychains/tonytoy-signing.keychain-db"
