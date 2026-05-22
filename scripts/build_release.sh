#!/bin/bash
set -e

# Determine the project root directory
# Assuming this script is in /scripts/ inside the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Navigate to project root
cd "$PROJECT_ROOT"

echo "Starting Release Build process..."
echo "Project Root: $PROJECT_ROOT"

# 1. Check dependencies
if ! command -v create-dmg &> /dev/null; then
    echo "Error: create-dmg is not installed."
    echo "Please run: brew install create-dmg"
    exit 1
fi

# 2. Resolve Version
echo "-----------------------------------"
if [ -z "${RELEASE_VERSION:-}" ]; then
    VERSION_LINE=$(grep "^version: " pubspec.yaml || true)
    if [ -z "$VERSION_LINE" ]; then
        echo "Error: 'version:' key not found in pubspec.yaml"
        exit 1
    fi

    RELEASE_VERSION=${VERSION_LINE#version: }
    RELEASE_VERSION=${RELEASE_VERSION%%+*}
fi

BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
ARTIFACT_NAME="${ARTIFACT_NAME:-MovieManager-${RELEASE_VERSION}-macos-arm64.dmg}"

echo "Release Version: $RELEASE_VERSION"
echo "Build Number: $BUILD_NUMBER"

# 3. Prepare Bundled Whisper Runtime
echo "-----------------------------------"
echo "Preparing bundled Whisper runtime..."
if [ -x "./scripts/prepare_whisper_runtime.sh" ]; then
    ./scripts/prepare_whisper_runtime.sh
else
    echo "Error: ./scripts/prepare_whisper_runtime.sh not found or not executable"
    exit 1
fi

# 4. Build Release APP
echo "-----------------------------------"
echo "Building Flutter Dependencies & MacOS Release..."
flutter pub get
flutter build macos --release --build-name "$RELEASE_VERSION" --build-number "$BUILD_NUMBER"

# 5. Define Names
APP_NAME="Media Manager"
APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
DIST_DIR="$PROJECT_ROOT/dist"
DMG_PATH="$DIST_DIR/$ARTIFACT_NAME"

# Verify App exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build failed. App not found at $APP_PATH"
    exit 1
fi

# 6. Bundle & Relocate Dependencies (Fix crash due to absolute paths)
echo "-----------------------------------"
if [ -x "./scripts/relocate_binaries.sh" ]; then
    ./scripts/relocate_binaries.sh "$APP_PATH"
else
    echo "Error: ./scripts/relocate_binaries.sh not found or not executable"
    exit 1
fi

# 7. Re-sign after relocation so added libraries are sealed in the app bundle
echo "-----------------------------------"
echo "Signing relocated app bundle..."
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
fi

ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$PROJECT_ROOT/macos/Runner/Release.entitlements}"
CODESIGN_ARGS=(--force --deep --sign "$SIGNING_IDENTITY")
if [ -f "$ENTITLEMENTS_PATH" ]; then
    CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS_PATH")
fi

codesign "${CODESIGN_ARGS[@]}" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# 8. Generate DMG
echo "-----------------------------------"
mkdir -p "$DIST_DIR"
echo "Packaging $DMG_PATH..."
if [ -f "$DMG_PATH" ]; then
    echo "Removing existing $DMG_PATH"
    rm "$DMG_PATH"
fi

create-dmg \
  --volname "$APP_NAME Installer" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 200 190 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 600 185 \
  "$DMG_PATH" \
  "$APP_PATH"

echo "-----------------------------------"
echo "✅ Build Complete!"
echo "DMG Location: $DMG_PATH"
