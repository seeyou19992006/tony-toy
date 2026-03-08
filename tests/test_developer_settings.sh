#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/scripts/developer-settings.sh"

if [ "$APP_NAME" != "TonyToy.app" ]; then
  echo "expected APP_NAME to be TonyToy.app, got: $APP_NAME"
  exit 1
fi

if [ "$BINARY_NAME" != "TonyToy" ]; then
  echo "expected BINARY_NAME to be TonyToy, got: $BINARY_NAME"
  exit 1
fi

if [ "$BUNDLE_ID" != "com.sxl.tonytoy" ]; then
  echo "expected default BUNDLE_ID to be com.sxl.tonytoy"
  exit 1
fi

if [ "$BUILD_DIR" != "dist/build" ]; then
  echo "expected BUILD_DIR to be dist/build, got: $BUILD_DIR"
  exit 1
fi

if [ "$PACKAGE_DIR" != "dist/package" ]; then
  echo "expected PACKAGE_DIR to be dist/package, got: $PACKAGE_DIR"
  exit 1
fi

if [[ ! "$DMG_NAME" == TonyToy-*.dmg ]]; then
  echo "expected DMG_NAME to match TonyToy-*.dmg, got: $DMG_NAME"
  exit 1
fi

TMP_OVERRIDE="$REPO_ROOT/scripts/developer-settings.local.sh"
trap 'rm -f "$TMP_OVERRIDE"' EXIT
cat > "$TMP_OVERRIDE" <<'LOCAL'
APP_NAME="CustomInputLayers.app"
BINARY_NAME="CustomInputLayers"
BUNDLE_ID="com.example.custominputlayers"
LOCAL

source "$REPO_ROOT/scripts/developer-settings.sh"
if [ -f "$TMP_OVERRIDE" ]; then
  source "$TMP_OVERRIDE"
fi

if [ "$APP_NAME" != "CustomInputLayers.app" ]; then
  echo "local override APP_NAME failed"
  exit 1
fi

if [ "$BINARY_NAME" != "CustomInputLayers" ]; then
  echo "local override BINARY_NAME failed"
  exit 1
fi

if [ "$BUNDLE_ID" != "com.example.custominputlayers" ]; then
  echo "local override BUNDLE_ID failed"
  exit 1
fi

echo "developer settings test passed"
