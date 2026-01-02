#!/bin/bash

# Path to pubspec.yaml
PUBSPEC="pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
    echo "Error: $PUBSPEC not found!"
    exit 1
fi

# Read current version line
# Expected format: version: 0.0.1
VERSION_LINE=$(grep "^version: " "$PUBSPEC")

if [ -z "$VERSION_LINE" ]; then
    echo "Error: 'version:' key not found in $PUBSPEC"
    exit 1
fi

# Extract version components
# Remove "version: " prefix
CURRENT_VERSION=${VERSION_LINE#version: }

# Check if there is a '+' (user requested no +, but just in case for safety/cleanup)
# If found, strip it for calculation, or handle error?
# We will assume strictly X.Y.Z format as requested.
# Strip anything after + just in case, but user said "Lets not use +"
CLEAN_VERSION=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)

# Split by dot
IFS='.' read -r -a PARTS <<< "$CLEAN_VERSION"

MAJOR=${PARTS[0]}
MINOR=${PARTS[1]}
PATCH=${PARTS[2]}

if [ -z "$MAJOR" ] || [ -z "$MINOR" ] || [ -z "$PATCH" ]; then
    echo "Error: Version format $CURRENT_VERSION not recognized. Expected X.Y.Z"
    exit 1
fi

# Increment Patch version
NEW_PATCH=$((PATCH + 1))

NEW_FULL_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

# Update pubspec.yaml
sed "s/^version: .*/version: $NEW_FULL_VERSION/" "$PUBSPEC" > "$PUBSPEC.tmp" && mv "$PUBSPEC.tmp" "$PUBSPEC"

echo "$NEW_FULL_VERSION"
