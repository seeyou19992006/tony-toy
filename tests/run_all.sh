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

bash "$REPO_ROOT/tests/test_developer_settings.sh"
bash "$REPO_ROOT/tests/test_package_signing_keychain.sh"

echo "all tests passed"
