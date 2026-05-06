#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/relocate_library_root.sh [--db /path/to/movie_manager.sqlite] OLD_ROOT NEW_ROOT

Examples:
  scripts/relocate_library_root.sh /mnt/myvideos /mnt/videos2
  scripts/relocate_library_root.sh --db "$HOME/Library/Containers/com.example.movieManager/Data/Library/Application Support/com.example.movieManager/movie_manager.sqlite" /mnt/myvideos /mnt/videos2

Environment:
  MOVIE_MANAGER_DB can be set instead of passing --db.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

normalize_root() {
  local value="$1"

  [[ -n "$value" ]] || die "path cannot be empty"

  while [[ "$value" != "/" && "$value" == */ ]]; do
    value="${value%/}"
  done

  printf '%s\n' "$value"
}

sql_literal() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

detect_db() {
  if [[ -n "${MOVIE_MANAGER_DB:-}" ]]; then
    printf '%s\n' "$MOVIE_MANAGER_DB"
    return
  fi

  local -a candidates=(
    "$HOME/Library/Containers/com.example.movieManager/Data/Library/Application Support/com.example.movieManager/movie_manager.sqlite"
    "$HOME/Library/Containers/com.example.movieManager/Data/Library/Application Support/Media Manager/movie_manager.sqlite"
    "$HOME/Library/Application Support/com.example.movieManager/movie_manager.sqlite"
    "$HOME/Library/Application Support/Media Manager/movie_manager.sqlite"
    "$HOME/Library/Application Support/MovieManager/movie_manager.sqlite"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  return 1
}

db_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)
      [[ $# -ge 2 ]] || die "--db requires a path"
      db_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -eq 2 ]] || {
  usage >&2
  exit 2
}

old_root="$(normalize_root "$1")"
new_root="$(normalize_root "$2")"

[[ "$old_root" != "$new_root" ]] || die "old and new roots are the same"

command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required"

if [[ -z "$db_path" ]]; then
  db_path="$(detect_db)" || die "could not find movie_manager.sqlite; pass --db or set MOVIE_MANAGER_DB"
fi

[[ -f "$db_path" ]] || die "database not found: $db_path"
[[ -r "$db_path" && -w "$db_path" ]] || die "database must be readable and writable: $db_path"

for sidecar in "$db_path-wal" "$db_path-shm"; do
  if [[ -e "$sidecar" ]]; then
    die "found SQLite sidecar $sidecar; close MovieManager and ensure pending writes are checkpointed before retrying"
  fi
done

table_count="$(
  sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('folders', 'videos');"
)"
[[ "$table_count" == "2" ]] || die "database does not contain MovieManager folders and videos tables"

integrity_check="$(sqlite3 "$db_path" "PRAGMA integrity_check;")"
[[ "$integrity_check" == "ok" ]] || die "database integrity check failed: $integrity_check"

old_sql="$(sql_literal "$old_root")"
new_sql="$(sql_literal "$new_root")"
match_suffix_sql="substr(PATH_COLUMN, 1, length($old_sql) + 1) = $old_sql || '/'"

folder_match_sql="path = $old_sql OR ${match_suffix_sql/PATH_COLUMN/path}"
video_match_sql="absolute_path = $old_sql OR ${match_suffix_sql/PATH_COLUMN/absolute_path}"

folders_to_update="$(sqlite3 "$db_path" "SELECT COUNT(*) FROM folders WHERE $folder_match_sql;")"
videos_to_update="$(sqlite3 "$db_path" "SELECT COUNT(*) FROM videos WHERE $video_match_sql;")"

if [[ "$folders_to_update" == "0" && "$videos_to_update" == "0" ]]; then
  echo "No database paths matched $old_root"
  exit 0
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_path="$db_path.backup-$timestamp"
cp -p "$db_path" "$backup_path"

sqlite3 "$db_path" <<SQL
.bail on
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

UPDATE folders
SET path = $new_sql || substr(path, length($old_sql) + 1)
WHERE $folder_match_sql;

UPDATE videos
SET
  absolute_path = $new_sql || substr(absolute_path, length($old_sql) + 1),
  is_offline = 0
WHERE $video_match_sql;

COMMIT;
SQL

echo "Updated $folders_to_update folder path(s) and $videos_to_update video path(s)."
echo "Backup written to: $backup_path"
