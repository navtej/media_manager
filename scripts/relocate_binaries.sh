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
RESOURCES_DIR="$APP_PATH/Contents/Resources"
WHISPER_RUNTIME_DIR="$RESOURCES_DIR/WhisperRuntime"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$FRAMEWORKS_DIR"
declare -a LOCAL_DEPENDENCY_DIRS=()

resolve_whisper_cli_source() {
    local candidates=()

    if [ -n "${WHISPER_CLI_PATH:-}" ]; then
        candidates+=("$WHISPER_CLI_PATH")
    fi

    candidates+=(
        "$PROJECT_ROOT/macos/Runner/WhisperRuntime/whisper-cli"
        "$PROJECT_ROOT/third_party/whisper.cpp/build/bin/whisper-cli"
        "$PROJECT_ROOT/third_party/whisper.cpp/build/bin/Release/whisper-cli"
        "$PROJECT_ROOT/build/whisper.cpp/bin/whisper-cli"
        "$PROJECT_ROOT/build/whisper.cpp/bin/Release/whisper-cli"
    )

    for candidate in "${candidates[@]}"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

bundle_whisper_runtime() {
    local source_cli

    if ! source_cli="$(resolve_whisper_cli_source)"; then
        if [ "${CONFIGURATION:-}" = "Release" ]; then
            echo "Error: whisper-cli runtime not found for release bundle." | tee -a "$LOG_FILE"
            echo "Expected an executable at macos/Runner/WhisperRuntime/whisper-cli, third_party/whisper.cpp/build/bin/whisper-cli, or WHISPER_CLI_PATH." | tee -a "$LOG_FILE"
            return 1
        fi

        rm -rf "$WHISPER_RUNTIME_DIR"
        echo "Warning: whisper-cli runtime not found; debug bundle will report bundled runtime missing." | tee -a "$LOG_FILE"
        return 0
    fi

    mkdir -p "$WHISPER_RUNTIME_DIR"
    local target_cli="$WHISPER_RUNTIME_DIR/whisper-cli"
    echo "Bundling whisper runtime from $source_cli" >> "$LOG_FILE"
    cp "$source_cli" "$target_cli"
    chmod 755 "$target_cli"
    LOCAL_DEPENDENCY_DIRS+=("$(dirname "$source_cli")")

    while read -r rpath_line; do
        local rpath=$(echo "$rpath_line" | sed -n 's/.*path \(.*\) (offset.*/\1/p')
        if [ -n "$rpath" ] && [[ "$rpath" == "$PROJECT_ROOT/"* ]]; then
            LOCAL_DEPENDENCY_DIRS+=("$rpath")
        fi
    done < <(otool -l "$source_cli" | grep -A2 LC_RPATH)

    return 0
}

bundle_whisper_runtime || exit 1

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
    
    if [ -z "$requested_path" ] || [[ "$requested_path" == "/usr/lib/"* ]] || [[ "$requested_path" == "/System/"* ]]; then
        return 0
    fi

    local real_src_path=""
    if [[ "$requested_path" == "/opt/homebrew/"* ]]; then
        real_src_path=$(readlink -f "$requested_path" 2>/dev/null)
        [ -z "$real_src_path" ] && real_src_path="$requested_path"
    elif [[ "$requested_path" == "$PROJECT_ROOT/"* ]] || [[ "$requested_path" == "/"* ]]; then
        real_src_path="$requested_path"
    elif [[ "$requested_path" == @rpath/* ]]; then
        local dependency_name="${requested_path#@rpath/}"
        for directory in "${LOCAL_DEPENDENCY_DIRS[@]}"; do
            if [ -f "$directory/$dependency_name" ]; then
                real_src_path="$directory/$dependency_name"
                break
            fi
        done
    else
        return 0
    fi

    # Find the REAL path (resolve symlinks)
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
    local marker="$target_lib.relocating"
    if [ -f "$marker" ]; then
        return 0
    fi
    touch "$marker"

    # Ensure canonical ID
    local current_id=$(otool -D "$target_lib" | tail -n 1)
    if [[ "$current_id" != "@rpath/$canonical_name" ]]; then
        echo "    [ID] Fixing ID of $canonical_name to @rpath/$canonical_name" >> "$LOG_FILE"
        install_name_tool -id "@rpath/$canonical_name" "$target_lib" 2>/dev/null && lib_modified=1
    fi

    # Fix dependencies of this library
    while IFS= read -r dep_line; do
        [[ "$dep_line" != [[:space:]]* ]] && continue
        local dep=$(echo "$dep_line" | awk '{print $1}')
        dep="${dep%:}"
        [ -z "$dep" ] && continue
        [[ "$dep" == "/usr/lib/"* ]] && continue
        [[ "$dep" == "/System/"* ]] && continue
        
        # Find the canonical name for THIS dependency
        local dep_real_path=""
        if [[ "$dep" == @rpath/* ]]; then
            local dep_name="${dep#@rpath/}"
            for directory in "${LOCAL_DEPENDENCY_DIRS[@]}"; do
                if [ -f "$directory/$dep_name" ]; then
                    dep_real_path="$directory/$dep_name"
                    break
                fi
            done
        else
            dep_real_path=$(readlink -f "$dep" 2>/dev/null)
            [ -z "$dep_real_path" ] && dep_real_path="$dep"
        fi
        [ -z "$dep_real_path" ] && continue
        local dep_canonical_name=$(basename "$dep_real_path")
        
        # Recurse
        if relocate_library "$dep"; then
            # Map the EXACT requested path to the CANONICAL name in the bundle
            if install_name_tool -change "$dep" "@rpath/$dep_canonical_name" "$target_lib" 2>/dev/null; then
                lib_modified=1
            fi
        fi
    done < <(otool -L "$target_lib")

    rm -f "$marker"
    [ "$lib_modified" -eq 1 ] && resign_file "$target_lib"
    return 0
}

# Function to process a single Mach-O file
process_macho() {
    local file_path="$1"
    local macho_modified=0
    local needs_relocation=0

    # 1. First scan for dependencies we know how to relocate
    while IFS= read -r dep_line; do
        [[ "$dep_line" != [[:space:]]* ]] && continue
        local dep=$(echo "$dep_line" | awk '{print $1}')
        dep="${dep%:}"
        if [[ "$dep" == "/opt/homebrew/"* ]] || [[ "$dep" == "$PROJECT_ROOT/"* ]]; then
            needs_relocation=1
            break
        fi
        if [[ "$dep" == @rpath/* ]]; then
            local dep_name="${dep#@rpath/}"
            for directory in "${LOCAL_DEPENDENCY_DIRS[@]}"; do
                if [ -f "$directory/$dep_name" ]; then
                    needs_relocation=1
                    break 2
                fi
            done
        fi
    done < <(otool -L "$file_path")

    if [ "$needs_relocation" -eq 0 ]; then
        return 0
    fi

    echo "Processing $(basename "$file_path")..." >> "$LOG_FILE"
    chmod +w "$file_path"

    # 2. Remove build-tree rpaths and add bundle-local rpaths
    while read -r rpath_line; do
        local existing_rpath=$(echo "$rpath_line" | sed -n 's/.*path \(.*\) (offset.*/\1/p')
        if [ -n "$existing_rpath" ] && [[ "$existing_rpath" == "$PROJECT_ROOT/"* ]]; then
            echo "  [RPATH] Removing build-tree rpath $existing_rpath from $(basename "$file_path")" >> "$LOG_FILE"
            install_name_tool -delete_rpath "$existing_rpath" "$file_path" 2>/dev/null && macho_modified=1
        fi
    done < <(otool -l "$file_path" | grep -A2 LC_RPATH)

    for rpath_val in "@executable_path/../Frameworks" "@loader_path/../../Frameworks" "@loader_path/Frameworks" "@loader_path/.."; do
        if ! otool -l "$file_path" | grep -q "$rpath_val"; then
            echo "  [RPATH] Adding $rpath_val to $(basename "$file_path")" >> "$LOG_FILE"
            install_name_tool -add_rpath "$rpath_val" "$file_path" 2>/dev/null && macho_modified=1
        fi
    done

    # 3. Relocate dependencies
    while IFS= read -r dep_line; do
        [[ "$dep_line" != [[:space:]]* ]] && continue
        local dep=$(echo "$dep_line" | awk '{print $1}')
        dep="${dep%:}"
        [ -z "$dep" ] && continue
        [[ "$dep" == "/usr/lib/"* ]] && continue
        [[ "$dep" == "/System/"* ]] && continue
        
        local dep_real_path=""
        if [[ "$dep" == @rpath/* ]]; then
            local dep_name="${dep#@rpath/}"
            for directory in "${LOCAL_DEPENDENCY_DIRS[@]}"; do
                if [ -f "$directory/$dep_name" ]; then
                    dep_real_path="$directory/$dep_name"
                    break
                fi
            done
        else
            dep_real_path=$(readlink -f "$dep" 2>/dev/null)
            [ -z "$dep_real_path" ] && dep_real_path="$dep"
        fi
        [ -z "$dep_real_path" ] && continue
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
