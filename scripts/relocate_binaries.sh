#!/bin/bash

# Canonical robust script to relocate Homebrew dependencies in a macOS app bundle.
# Usage: ./relocate_binaries.sh path/to/YourApp.app

APP_PATH="$1"
LOG_FILE="/tmp/movie_manager_relocate.log"

echo "=== Relocation Started: $(date) ===" > "$LOG_FILE"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 <path_to_app_bundle>" | tee -a "$LOG_FILE"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found at $APP_PATH" | tee -a "$LOG_FILE"
    exit 1
fi

APP_PATH=$(realpath "$APP_PATH")
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

# Function to re-sign a binary/library
resign_file() {
    local file_path="$1"
    echo "  [SIGN] Re-signing $(basename "$file_path")..." >> "$LOG_FILE"
    codesign --remove-signature "$file_path" 2>/dev/null
    codesign --force --sign - "$file_path" 2>/dev/null
}

# Function to relocate a library and its dependencies
relocate_library() {
    local requested_path="$1"
    requested_path="${requested_path%:}" # Strip trailing colon
    
    if [ -z "$requested_path" ] || [[ "$requested_path" != "/opt/homebrew/"* ]]; then
        return 0
    fi

    # Find the REAL path (resolve symlinks)
    local real_src_path=$(readlink -f "$requested_path" 2>/dev/null)
    
    if [ -z "$real_src_path" ] || [ ! -f "$real_src_path" ]; then
        # Fallback to the requested path itself if readlink fails (unlikely for existing files)
        real_src_path="$requested_path"
    fi

    # Canonical name is the basename of the REAL path
    local canonical_name=$(basename "$real_src_path")
    local target_lib="$FRAMEWORKS_DIR/$canonical_name"

    # Bundle the real file
    if [ ! -f "$target_lib" ]; then
        if [ -f "$real_src_path" ]; then
            echo "  [BUNDLE] Bundling canonical $canonical_name..." >> "$LOG_FILE"
            cp "$real_src_path" "$target_lib"
            chmod +w "$target_lib"
        else
            echo "  [CRITICAL] Dependency $requested_path not found on system!" | tee -a "$LOG_FILE"
            local formula=$(echo "$requested_path" | sed -n 's|.*/opt/\([^/]*\)/.*|\1|p')
            [ -z "$formula" ] && formula=$(echo "$requested_path" | awk -F'/' '{print $4}')
            echo "  [TIP] Try running: brew install $formula" | tee -a "$LOG_FILE"
            return 1
        fi
    fi

    local lib_modified=0

    # Ensure canonical ID
    local current_id=$(otool -D "$target_lib" | tail -n 1)
    if [[ "$current_id" != "@rpath/$canonical_name" ]]; then
        echo "    [ID] Fixing ID of $canonical_name to @rpath/$canonical_name" >> "$LOG_FILE"
        install_name_tool -id "@rpath/$canonical_name" "$target_lib" 2>/dev/null && lib_modified=1
    fi

    # Fix dependencies of this library
    while read -r dep_line; do
        local dep=$(echo "$dep_line" | awk '{print $1}')
        dep="${dep%:}"
        [ -z "$dep" ] || [[ "$dep" != "/opt/homebrew/"* ]] && continue
        
        # Find the canonical name for THIS dependency
        local dep_real_path=$(readlink -f "$dep" 2>/dev/null)
        [ -z "$dep_real_path" ] && dep_real_path="$dep"
        local dep_canonical_name=$(basename "$dep_real_path")
        
        # Recurse
        if relocate_library "$dep"; then
            # Map the EXACT requested path to the CANONICAL name in the bundle
            if install_name_tool -change "$dep" "@rpath/$dep_canonical_name" "$target_lib" 2>/dev/null; then
                lib_modified=1
            fi
        fi
    done < <(otool -L "$target_lib")

    [ "$lib_modified" -eq 1 ] && resign_file "$target_lib"
    return 0
}

# Function to process a single Mach-O file
process_macho() {
    local file_path="$1"
    local macho_modified=0
    local has_homebrew=0

    # 1. First scan for Homebrew dependencies
    while read -r dep_line; do
        local dep=$(echo "$dep_line" | awk '{print $1}')
        dep="${dep%:}"
        if [[ "$dep" == "/opt/homebrew/"* ]]; then
            has_homebrew=1
            break
        fi
    done < <(otool -L "$file_path")

    if [ "$has_homebrew" -eq 0 ]; then
        return 0
    fi

    echo "Processing $(basename "$file_path")..." >> "$LOG_FILE"
    chmod +w "$file_path"

    # 2. Add rpaths
    for rpath_val in "@executable_path/../Frameworks" "@loader_path/Frameworks" "@loader_path/.."; do
        if ! otool -l "$file_path" | grep -q "$rpath_val"; then
            echo "  [RPATH] Adding $rpath_val to $(basename "$file_path")" >> "$LOG_FILE"
            install_name_tool -add_rpath "$rpath_val" "$file_path" 2>/dev/null && macho_modified=1
        fi
    done

    # 3. Relocate dependencies
    while read -r dep_line; do
        local dep=$(echo "$dep_line" | awk '{print $1}')
        dep="${dep%:}"
        [ -z "$dep" ] || [[ "$dep" != "/opt/homebrew/"* ]] && continue
        
        local dep_real_path=$(readlink -f "$dep" 2>/dev/null)
        [ -z "$dep_real_path" ] && dep_real_path="$dep"
        local dep_canonical_name=$(basename "$dep_real_path")
        
        if relocate_library "$dep"; then
            echo "  [FIX] Relocating $dep to @rpath/$dep_canonical_name in $(basename "$file_path")" >> "$LOG_FILE"
            if install_name_tool -change "$dep" "@rpath/$dep_canonical_name" "$file_path" 2>/dev/null; then
                macho_modified=1
            fi
        else
            echo "  [ERR] Skipping relocation for $(basename "$dep") (bundle failed)" >> "$LOG_FILE"
        fi
    done < <(otool -L "$file_path")

    [ "$macho_modified" -eq 1 ] && resign_file "$file_path"
}

echo "Scanning for Mach-O binaries..." >> "$LOG_FILE"

find "$APP_PATH" -type f | while read -r file; do
    if [[ "$file" == *"__preview.dylib"* ]] || [[ "$file" == *"_hotreload_"* ]]; then
        continue
    fi

    if file "$file" | grep -q "Mach-O"; then
        process_macho "$file"
    fi
done

echo "=== Relocation Complete: $(date) ===" >> "$LOG_FILE"
echo "Relocation complete. Log: $LOG_FILE"
