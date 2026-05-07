#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

APP_PATH="$TMP_DIR/Media Manager.app"
SOURCE_DIR="$TMP_DIR/source"
mkdir -p "$APP_PATH/Contents/MacOS" "$SOURCE_DIR"

SOURCE_CLI="$SOURCE_DIR/whisper-cli"
cat > "$SOURCE_CLI" <<'SCRIPT'
#!/bin/bash
echo "fake whisper runtime"
SCRIPT
chmod +x "$SOURCE_CLI"

WHISPER_CLI_PATH="$SOURCE_CLI" \
  "$PROJECT_ROOT/scripts/relocate_binaries.sh" "$APP_PATH" >/dev/null

BUNDLED_CLI="$APP_PATH/Contents/Resources/WhisperRuntime/whisper-cli"
if [ ! -x "$BUNDLED_CLI" ]; then
  echo "Expected bundled whisper-cli at $BUNDLED_CLI"
  exit 1
fi

if ! cmp -s "$SOURCE_CLI" "$BUNDLED_CLI"; then
  echo "Bundled whisper-cli differs from source"
  exit 1
fi

echo "Bundled whisper runtime test passed."
