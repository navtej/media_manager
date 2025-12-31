#!/bin/bash

# Path to pubspec.yaml
PUBSPEC="pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
    echo "Error: $PUBSPEC not found!"
    exit 1
fi

# Read current version line
# Expected format: version: 1.0.0+1
VERSION_LINE=$(grep "^version: " "$PUBSPEC")

if [ -z "$VERSION_LINE" ]; then
    echo "Error: 'version:' key not found in $PUBSPEC"
    exit 1
fi

# Extract version components
# Remove "version: " prefix
CURRENT_FULL_VERSION=${VERSION_LINE#version: }

# Split dimensions
# Assuming format X.Y.Z+N
BASE_VERSION=$(echo "$CURRENT_FULL_VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$CURRENT_FULL_VERSION" | cut -d'+' -f2)

if [ -z "$BUILD_NUMBER" ] || [ "$BUILD_NUMBER" == "$BASE_VERSION" ]; then
    # Case where there is no +N, e.g. 1.0.0. Initialize build number to 1
    NEW_BUILD_NUMBER=1
else
    NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
fi

NEW_FULL_VERSION="${BASE_VERSION}+${NEW_BUILD_NUMBER}"

# Update pubspec.yaml
# Use sed to replace the line
# -i '' for macOS sed compatibility (no backup)
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version: .*/version: $NEW_FULL_VERSION/" "$PUBSPEC"
else
  sed -i "s/^version: .*/version: $NEW_FULL_VERSION/" "$PUBSPEC"
fi

echo "$NEW_FULL_VERSION"
