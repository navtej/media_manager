#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_CLI="$PROJECT_ROOT/macos/Runner/WhisperRuntime/whisper-cli"

if [ ! -x "$SOURCE_CLI" ]; then
  echo "Skipping whisper runtime relocation test; run scripts/prepare_whisper_runtime.sh first."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

APP_PATH="$TMP_DIR/Media Manager.app"
mkdir -p "$APP_PATH/Contents/MacOS"

"$PROJECT_ROOT/scripts/relocate_binaries.sh" "$APP_PATH" >/dev/null

BUNDLED_CLI="$APP_PATH/Contents/Resources/WhisperRuntime/whisper-cli"
if [ ! -x "$BUNDLED_CLI" ]; then
  echo "Expected bundled whisper-cli at $BUNDLED_CLI"
  exit 1
fi

if ! find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -name 'libwhisper*.dylib' | grep -q .; then
  echo "Expected libwhisper dylib in app Frameworks"
  exit 1
fi

if otool -l "$BUNDLED_CLI" | grep -q "$PROJECT_ROOT/third_party/whisper.cpp"; then
  echo "Bundled whisper-cli still contains build-tree rpaths"
  exit 1
fi

if ! otool -l "$BUNDLED_CLI" | grep -q '@loader_path/../../Frameworks'; then
  echo "Bundled whisper-cli is missing Resources-to-Frameworks rpath"
  exit 1
fi

echo "Whisper runtime relocation test passed."
