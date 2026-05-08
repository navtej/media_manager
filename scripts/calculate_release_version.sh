#!/bin/bash
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: calculate_release_version.sh must run inside a Git worktree." >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  git fetch --tags --quiet origin
fi

if [ -n "${RELEASE_DATE_UTC:-}" ]; then
  if [[ ! "$RELEASE_DATE_UTC" =~ ^([0-9]{4})-([0-9]{1,2})$ ]]; then
    echo "Error: RELEASE_DATE_UTC must use YYYY-M or YYYY-MM format." >&2
    exit 1
  fi

  year="${BASH_REMATCH[1]}"
  month_number=$((10#${BASH_REMATCH[2]}))
else
  year="$(date -u +%Y)"
  month_number=$((10#$(date -u +%m)))
fi

if [ "$month_number" -lt 1 ] || [ "$month_number" -gt 12 ]; then
  echo "Error: release month must be between 1 and 12." >&2
  exit 1
fi

month="$month_number"
max_patch=-1

while IFS= read -r tag; do
  if [[ "$tag" =~ ^v${year}\.${month}\.([0-9]+)$ ]]; then
    patch=$((10#${BASH_REMATCH[1]}))
    if [ "$patch" -gt "$max_patch" ]; then
      max_patch="$patch"
    fi
  fi
done < <(git tag --list "v${year}.${month}.*")

patch=$((max_patch + 1))
version="${year}.${month}.${patch}"
tag="v${version}"
build_number="${GITHUB_RUN_NUMBER:-0}"
artifact_name="MovieManager-${version}-macos-arm64.dmg"

emit() {
  local name="$1"
  local value="$2"

  echo "${name}=${value}"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

emit VERSION "$version"
emit TAG "$tag"
emit BUILD_NUMBER "$build_number"
emit ARTIFACT_NAME "$artifact_name"
