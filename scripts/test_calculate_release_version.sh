#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SUBJECT="$PROJECT_ROOT/scripts/calculate_release_version.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

make_repo() {
  local repo="$1"

  git init -q "$repo"
  git -C "$repo" config user.email "release-test@example.invalid"
  git -C "$repo" config user.name "Release Test"
  echo "fixture" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial"
}

run_subject() {
  local repo="$1"

  (
    cd "$repo"
    RELEASE_DATE_UTC=2026-05 GITHUB_RUN_NUMBER=42 "$SUBJECT"
  )
}

field() {
  local output="$1"
  local name="$2"

  printf '%s\n' "$output" | sed -n "s/^${name}=//p"
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

repo="$TMP_ROOT/no-tags"
make_repo "$repo"
output="$(run_subject "$repo")"
assert_eq "2026.5.0" "$(field "$output" VERSION)" "no current-month tags version"
assert_eq "v2026.5.0" "$(field "$output" TAG)" "no current-month tags tag"
assert_eq "42" "$(field "$output" BUILD_NUMBER)" "build number"
assert_eq "MovieManager-2026.5.0-macos-arm64.dmg" "$(field "$output" ARTIFACT_NAME)" "artifact name"

repo="$TMP_ROOT/current-tag"
make_repo "$repo"
git -C "$repo" tag v2026.5.0
output="$(run_subject "$repo")"
assert_eq "2026.5.1" "$(field "$output" VERSION)" "current-month tag increments patch"

repo="$TMP_ROOT/other-month"
make_repo "$repo"
git -C "$repo" tag v2026.4.9
git -C "$repo" tag v2025.5.7
output="$(run_subject "$repo")"
assert_eq "2026.5.0" "$(field "$output" VERSION)" "other months ignored"

repo="$TMP_ROOT/invalid-tags"
make_repo "$repo"
git -C "$repo" tag v2026.5.alpha
git -C "$repo" tag v2026.5.1-extra
git -C "$repo" tag release-2026.5.3
git -C "$repo" tag v2026.5.2
output="$(run_subject "$repo")"
assert_eq "2026.5.3" "$(field "$output" VERSION)" "invalid current-month tags ignored"

echo "calculate_release_version tests passed"
