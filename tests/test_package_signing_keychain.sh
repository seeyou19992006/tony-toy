#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/fake-bin"
LOG_DIR="$TMP_DIR/logs"
mkdir -p "$FAKE_BIN" "$LOG_DIR"

cat > "$FAKE_BIN/codesign" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "$*" > "$TONYTOY_TEST_CODESIGN_LOG"
exit 0
EOF

cat > "$FAKE_BIN/hdiutil" <<'EOF'
#!/bin/bash
set -euo pipefail
subcommand="${1:-}"
case "$subcommand" in
  create)
    out="${@: -1}"
    touch "$out"
    ;;
  attach)
    echo "/dev/disk9 Apple_HFS /Volumes/TonyToy"
    ;;
  detach)
    ;;
  convert)
    out=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-o" ]; then
        out="$2"
        shift 2
        continue
      fi
      shift
    done
    touch "$out"
    ;;
  *)
    echo "unexpected hdiutil subcommand: $subcommand" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$FAKE_BIN/codesign" "$FAKE_BIN/hdiutil"

mkdir -p "$REPO_ROOT/dist/build/TonyToy.app/Contents/MacOS"
touch "$REPO_ROOT/dist/build/TonyToy.app/Contents/MacOS/TonyToy"
chmod +x "$REPO_ROOT/dist/build/TonyToy.app/Contents/MacOS/TonyToy"

codesign_log="$LOG_DIR/codesign.log"
PATH="$FAKE_BIN:$PATH" \
  SIGN_KEYCHAIN="/tmp/tonytoy-signing.keychain-db" \
  TONYTOY_TEST_CODESIGN_LOG="$codesign_log" \
  "$REPO_ROOT/scripts/package.sh" >/dev/null

if ! grep -q -- "--keychain /tmp/tonytoy-signing.keychain-db" "$codesign_log"; then
  echo "expected package.sh to pass --keychain to codesign when SIGN_KEYCHAIN is set"
  echo "actual codesign args: $(cat "$codesign_log")"
  exit 1
fi

echo "package signing keychain test passed"
