#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WHISPER_CPP_REF="${WHISPER_CPP_REF:-v1.7.6}"
SOURCE_DIR="$PROJECT_ROOT/third_party/whisper.cpp"
RUNTIME_DIR="$PROJECT_ROOT/macos/Runner/WhisperRuntime"
RUNTIME_CLI="$RUNTIME_DIR/whisper-cli"

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required to prepare the bundled Whisper runtime."
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "Error: cmake is required to build the bundled Whisper runtime."
  exit 1
fi

mkdir -p "$PROJECT_ROOT/third_party"

if [ ! -d "$SOURCE_DIR/.git" ]; then
  git clone --depth 1 --branch "$WHISPER_CPP_REF" \
    https://github.com/ggml-org/whisper.cpp.git "$SOURCE_DIR"
else
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$WHISPER_CPP_REF"
  git -C "$SOURCE_DIR" checkout "$WHISPER_CPP_REF"
fi

cmake -S "$SOURCE_DIR" -B "$SOURCE_DIR/build" \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON
cmake --build "$SOURCE_DIR/build" --target whisper-cli --config Release

SOURCE_CLI="$SOURCE_DIR/build/bin/whisper-cli"
if [ ! -x "$SOURCE_CLI" ] && [ -x "$SOURCE_DIR/build/bin/Release/whisper-cli" ]; then
  SOURCE_CLI="$SOURCE_DIR/build/bin/Release/whisper-cli"
fi

if [ ! -x "$SOURCE_CLI" ]; then
  echo "Error: whisper-cli build output was not found."
  exit 1
fi

mkdir -p "$RUNTIME_DIR"
cp "$SOURCE_CLI" "$RUNTIME_CLI"
chmod 755 "$RUNTIME_CLI"

echo "Prepared bundled Whisper runtime at $RUNTIME_CLI"
