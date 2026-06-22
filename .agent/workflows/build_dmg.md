---
description: Publish a macOS release DMG and update the Homebrew cask
---

Use this workflow when making a real MovieManager release. Releases are built by
GitHub Actions from `main`; the Homebrew cask is updated separately in
`/Users/navtej/work/homebrew-tap`.

## Preconditions

1. Confirm the app checkout is on `main` and clean:
   ```bash
   git fetch origin --prune --tags
   git status --short --branch
   git log --oneline --decorate origin/main..HEAD
   ```

2. Confirm GitHub CLI is available and authenticated:
   ```bash
   gh --version
   gh auth status
   ```

3. Verify release version calculation when release scripts changed:
   ```bash
   bash scripts/test_calculate_release_version.sh
   ./scripts/calculate_release_version.sh
   ```

## GitHub Release

1. Dispatch the release workflow from `main`:
   ```bash
   gh workflow run release.yml -f dry_run=false --ref main --repo navtej/media_manager
   ```

2. Get the new run ID and watch it to completion:
   ```bash
   gh run list --repo navtej/media_manager --workflow release.yml --branch main --limit 5
   gh run watch <run-id> --repo navtej/media_manager --exit-status
   ```

   If `gh run watch` flakes, query the run directly:
   ```bash
   gh run view <run-id> --repo navtej/media_manager --json status,conclusion,url,headSha
   ```

3. Confirm the published release and capture the asset checksum:
   ```bash
   TAG=vYYYY.MM.DD.P
   gh release view "$TAG" --repo navtej/media_manager --json tagName,url,targetCommitish,publishedAt,assets

   tmpdir="$(mktemp -d /private/tmp/moviemanager-release-XXXXXX)"
   gh release download "$TAG" --repo navtej/media_manager --pattern '*.sha256' --dir "$tmpdir"
   cat "$tmpdir"/*.sha256
   ```

## Homebrew Tap Update

1. Update the tap checkout:
   ```bash
   cd /Users/navtej/work/homebrew-tap
   git fetch origin --prune
   git status --short --branch
   ```

2. Edit `Casks/media-manager.rb`:
   - set `version` to the new release version without the leading `v`
   - set `sha256` to the published DMG SHA-256
   - leave the URL template pointing at the GitHub release asset:
     `https://github.com/navtej/media_manager/releases/download/v#{version}/MovieManager-#{version}-macos-arm64.dmg`

3. Verify, commit, and push the tap change:
   ```bash
   ruby -c Casks/media-manager.rb
   git diff --check
   git diff -- Casks/media-manager.rb
   git add Casks/media-manager.rb
   git commit -m "Update media-manager cask to <version>"
   git push origin main
   ```

   If SSH push fails with `Permission denied (publickey)` but `gh auth status`
   succeeds, use the authenticated HTTPS path for the push:
   ```bash
   git -c url.https://github.com/.insteadOf=git@github.com: push origin main
   ```

## Brew Update And Verification

1. Refresh Homebrew so `navtej/tap` sees the pushed cask:
   ```bash
   brew update
   ```

2. Verify the MovieManager cask through the tapped token:
   ```bash
   HOMEBREW_NO_AUTO_UPDATE=1 brew fetch --cask --force --retry navtej/tap/media-manager
   HOMEBREW_NO_AUTO_UPDATE=1 brew style --cask navtej/tap/media-manager
   HOMEBREW_NO_AUTO_UPDATE=1 brew info --cask navtej/tap/media-manager
   HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --cask media-manager
   ```

3. Verify the installed app bundle:
   ```bash
   codesign --verify --deep --strict --verbose=2 '/Applications/Media Manager.app'
   defaults read '/Applications/Media Manager.app/Contents/Info' CFBundleShortVersionString
   defaults read '/Applications/Media Manager.app/Contents/Info' CFBundleVersion
   HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --cask media-manager
   ```

Notes:
- `brew fetch` and `brew style` must use `navtej/tap/media-manager`, not a raw
  local cask file path.
- If `brew update` reports unrelated third-party tap warnings, still run the
  focused `HOMEBREW_NO_AUTO_UPDATE=1` checks against `navtej/tap/media-manager`
  before treating the MovieManager release as blocked.
