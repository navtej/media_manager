#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/relocate_library_root.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DB="$TMP_DIR/movie_manager.sqlite"
OLD_ROOT="/mnt/myvideos"
NEW_ROOT="/mnt/videos2"

sqlite3 "$DB" <<SQL
CREATE TABLE folders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  alias TEXT,
  added_at TEXT
);

CREATE TABLE videos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  folder_id INTEGER NOT NULL,
  absolute_path TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  is_offline INTEGER NOT NULL DEFAULT 0
);

INSERT INTO folders (id, path, alias, added_at) VALUES
  (1, '/mnt/myvideos', 'myvideos', '2026-05-05'),
  (2, '/mnt/myvideos2', 'myvideos2', '2026-05-05'),
  (3, '/mnt/other', 'other', '2026-05-05');

INSERT INTO videos (id, folder_id, absolute_path, title, is_offline) VALUES
  (1, 1, '/mnt/myvideos/movie.mp4', 'movie', 1),
  (2, 1, '/mnt/myvideos/Nested/clip.mkv', 'clip', 1),
  (3, 2, '/mnt/myvideos2/untouched.mp4', 'untouched', 1),
  (4, 3, '/mnt/other/other.mp4', 'other', 1);
SQL

"$SCRIPT" --db "$DB" "$OLD_ROOT" "$NEW_ROOT" >/dev/null

folders="$(sqlite3 "$DB" "SELECT path FROM folders ORDER BY id;")"
expected_folders="/mnt/videos2
/mnt/myvideos2
/mnt/other"
if [[ "$folders" != "$expected_folders" ]]; then
  echo "Unexpected folders:"
  echo "$folders"
  exit 1
fi

videos="$(sqlite3 "$DB" "SELECT absolute_path || '|' || is_offline FROM videos ORDER BY id;")"
expected_videos="/mnt/videos2/movie.mp4|0
/mnt/videos2/Nested/clip.mkv|0
/mnt/myvideos2/untouched.mp4|1
/mnt/other/other.mp4|1"
if [[ "$videos" != "$expected_videos" ]]; then
  echo "Unexpected videos:"
  echo "$videos"
  exit 1
fi

backup_count="$(find "$TMP_DIR" -maxdepth 1 -name 'movie_manager.sqlite.backup-*' -type f | wc -l | tr -d ' ')"
if [[ "$backup_count" != "1" ]]; then
  echo "Expected one backup, found $backup_count"
  exit 1
fi

echo "relocate_library_root.sh test passed"
