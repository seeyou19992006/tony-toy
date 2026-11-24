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

swiftc "$REPO_ROOT/src/MenuStateStore.swift" "$REPO_ROOT/tests/MenuStateStoreTests.swift" -o /tmp/menu-state-tests
/tmp/menu-state-tests

swiftc "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/tests/JSONValueTests.swift" \
       -o /tmp/jsonvalue-tests
/tmp/jsonvalue-tests

swiftc "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/src/Core/TonyToyConfig.swift" \
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

bash "$REPO_ROOT/tests/test_developer_settings.sh"
bash "$REPO_ROOT/tests/test_package_signing_keychain.sh"

echo "all tests passed"
