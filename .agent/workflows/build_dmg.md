---
description: Build MacOS Release DMG with Auto-Versioning
---

Follow these steps to automatically increment the version, build the release, and package it.

1.  **Install dependencies** (if not already installed):
    ```bash
    brew install create-dmg
    ```

2.  **Versioning and Build**:
    Run the following block to increment the version, build, and package:

    ```bash
    # 1. Increment Version
    echo "Incrementing version..."
    NEW_VERSION=$(./scripts/update_version.sh)
    echo "New Version: $NEW_VERSION"

    # 2. Build Release APP
    echo "Building Release..."
    flutter build macos --release

    # 3. Define Names
    APP_NAME="Media Manager"
    DMG_NAME="Media_Manager_v${NEW_VERSION}.dmg"
    APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"

    # 4. Generate DMG
    echo "Packaging $DMG_NAME..."
    test -f "$DMG_NAME" && rm "$DMG_NAME"

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
    
    echo "Done! Created at $DMG_NAME"
    ```