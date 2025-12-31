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

# 2. Increment Version
echo "-----------------------------------"
echo "Incrementing Version..."
if [ -x "./scripts/update_version.sh" ]; then
    NEW_VERSION=$(./scripts/update_version.sh)
else
    # Try to make it executable if it exists but isn't executable
    if [ -f "./scripts/update_version.sh" ]; then
        chmod +x ./scripts/update_version.sh
        NEW_VERSION=$(./scripts/update_version.sh)
    else
        echo "Error: ./scripts/update_version.sh not found."
        exit 1
    fi
fi
echo "New Version: $NEW_VERSION"

# 3. Build Release APP
echo "-----------------------------------"
echo "Building Flutter Dependencies & MacOS Release..."
flutter pub get
flutter build macos --release

# 4. Define Names
APP_NAME="Media Manager"
DMG_NAME="Media_Manager_v${NEW_VERSION}.dmg"
APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"

# Verify App exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build failed. App not found at $APP_PATH"
    exit 1
fi

# 5. Generate DMG
echo "-----------------------------------"
echo "Packaging $DMG_NAME..."
if [ -f "$DMG_NAME" ]; then
    echo "Removing existing $DMG_NAME"
    rm "$DMG_NAME"
fi

create-dmg \
  --volname "$APP_NAME Installer" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 200 190 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 600 185 \
  "$DMG_NAME" \
  "$APP_PATH"

echo "-----------------------------------"
echo "✅ Build Complete!"
echo "DMG Location: $PROJECT_ROOT/$DMG_NAME"
