#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$REPO_ROOT/README.md" ]; then
  echo "README.md is required"
  exit 1
fi

if [ ! -x "$REPO_ROOT/scripts/build.sh" ] || [ ! -x "$REPO_ROOT/scripts/package.sh" ]; then
  echo "scripts/build.sh/package.sh must all be executable"
  exit 1
fi

swiftc "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/tests/JSONValueTests.swift" \
       -o /tmp/jsonvalue-tests
/tmp/jsonvalue-tests

swiftc "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/src/Core/TonyToyConfig.swift" \
       "$REPO_ROOT/src/Core/ConfigStore.swift" \
       "$REPO_ROOT/src/Core/ConfigMigrator.swift" \
       "$REPO_ROOT/src/Core/HotkeyKeySpec.swift" \
       "$REPO_ROOT/src/Core/Feature.swift" \
       "$REPO_ROOT/src/Core/FeatureRegistry.swift" \
       "$REPO_ROOT/src/DebugLog.swift" \
       "$REPO_ROOT/tests/ConfigStoreTests.swift" \
       -o /tmp/config-tests
/tmp/config-tests

swiftc "$REPO_ROOT/src/PasswordEntry.swift" \
       "$REPO_ROOT/src/VaultCryptoService.swift" \
       "$REPO_ROOT/src/VaultService.swift" \
       "$REPO_ROOT/src/PBKDF2.swift" \
       "$REPO_ROOT/tests/VaultServiceTests.swift" \
       -framework CryptoKit -framework Foundation -o /tmp/vault-tests
/tmp/vault-tests

swiftc "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/src/Core/TonyToyConfig.swift" \
       "$REPO_ROOT/src/Core/ConfigStore.swift" \
       "$REPO_ROOT/src/Core/ConfigMigrator.swift" \
       "$REPO_ROOT/src/Core/HotkeyKeySpec.swift" \
       "$REPO_ROOT/src/Core/Feature.swift" \
       "$REPO_ROOT/src/DebugLog.swift" \
       "$REPO_ROOT/src/KeyConfigSupport.swift" \
       "$REPO_ROOT/src/InputAliasRegistry.swift" \
       "$REPO_ROOT/src/AppAction.swift" \
       "$REPO_ROOT/src/ScreenCoordinateConverter.swift" \
       "$REPO_ROOT/src/WindowIdentityResolver.swift" \
       "$REPO_ROOT/src/WindowMovementPlanner.swift" \
       "$REPO_ROOT/src/AppActionExecutor.swift" \
       "$REPO_ROOT/tests/WindowMovementTests.swift" \
       -framework Cocoa -framework Carbon -framework ApplicationServices -o /tmp/window-movement-tests
/tmp/window-movement-tests

swiftc "$REPO_ROOT/src/DebugLog.swift" \
       "$REPO_ROOT/src/Pinyin.swift" \
       "$REPO_ROOT/src/KeyConfigSupport.swift" \
       "$REPO_ROOT/src/InputAliasRegistry.swift" \
       "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/src/Core/TonyToyConfig.swift" \
       "$REPO_ROOT/src/Core/ConfigStore.swift" \
       "$REPO_ROOT/src/Core/ConfigMigrator.swift" \
       "$REPO_ROOT/src/Core/HotkeyKeySpec.swift" \
       "$REPO_ROOT/src/Core/Feature.swift" \
       "$REPO_ROOT/src/AppIndex.swift" \
       "$REPO_ROOT/src/Activator.swift" \
       "$REPO_ROOT/src/IconCache.swift" \
       "$REPO_ROOT/src/WindowEnumerator.swift" \
       "$REPO_ROOT/src/WindowedApps.swift" \
       "$REPO_ROOT/src/UI/AppearanceAwareViews.swift" \
       "$REPO_ROOT/src/SwitcherWindow.swift" \
       "$REPO_ROOT/src/SwitcherController.swift" \
       "$REPO_ROOT/tests/SwitcherAndPinyinTests.swift" \
       -framework Cocoa -framework Carbon -framework ApplicationServices -o /tmp/switcher-pinyin-tests
/tmp/switcher-pinyin-tests

bash "$REPO_ROOT/tests/test_developer_settings.sh"
bash "$REPO_ROOT/tests/test_package_signing_keychain.sh"

echo "all tests passed"
