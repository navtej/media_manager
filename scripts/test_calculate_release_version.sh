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
    RELEASE_DATE_UTC=2026-06-11 GITHUB_RUN_NUMBER=42 "$SUBJECT"
  )
}

run_subject_with_date() {
  local repo="$1"
  local release_date="$2"

  (
    cd "$repo"
    RELEASE_DATE_UTC="$release_date" GITHUB_RUN_NUMBER=42 "$SUBJECT"
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
assert_eq "2026.06.11.0" "$(field "$output" VERSION)" "no same-day tags version"
assert_eq "v2026.06.11.0" "$(field "$output" TAG)" "no same-day tags tag"
assert_eq "42" "$(field "$output" BUILD_NUMBER)" "build number"
assert_eq "MovieManager-2026.06.11.0-macos-arm64.dmg" "$(field "$output" ARTIFACT_NAME)" "artifact name"

repo="$TMP_ROOT/same-day-tag"
make_repo "$repo"
git -C "$repo" tag v2026.06.11.0
output="$(run_subject "$repo")"
assert_eq "2026.06.11.1" "$(field "$output" VERSION)" "same-day tag increments patch"

repo="$TMP_ROOT/other-day"
make_repo "$repo"
git -C "$repo" tag v2026.06.10.9
git -C "$repo" tag v2026.05.11.7
git -C "$repo" tag v2026.6.0
git -C "$repo" tag v0.0.9
output="$(run_subject "$repo")"
assert_eq "2026.06.11.0" "$(field "$output" VERSION)" "other dates and legacy tags ignored"

repo="$TMP_ROOT/invalid-tags"
make_repo "$repo"
git -C "$repo" tag v2026.06.11.alpha
git -C "$repo" tag v2026.06.11.1-extra
git -C "$repo" tag release-2026.06.11.3
git -C "$repo" tag v2026.06.11.2
output="$(run_subject "$repo")"
assert_eq "2026.06.11.3" "$(field "$output" VERSION)" "invalid same-day tags ignored"

repo="$TMP_ROOT/invalid-date"
make_repo "$repo"
set +e
output="$(run_subject_with_date "$repo" 2026-06 2>&1)"
status="$?"
set -e
if [ "$status" -eq 0 ]; then
  fail "invalid RELEASE_DATE_UTC should fail"
fi
case "$output" in
  *"RELEASE_DATE_UTC must use YYYY-MM-DD format."*) ;;
  *) fail "invalid RELEASE_DATE_UTC error message: expected YYYY-MM-DD guidance, got '$output'" ;;
esac

echo "calculate_release_version tests passed"
