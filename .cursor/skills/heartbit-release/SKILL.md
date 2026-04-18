---
name: heartbit-release
description: >-
  Prepare a HeartBit macOS release: version bump, Homebrew cask update, git tag,
  and GitHub release. Use when the user wants to publish, ship a version, cut a
  release, or update the tap/cask.
---

# HeartBit release and publish

## Goal

Ship a new **marketing version** (e.g. `1.3.5`) with:

- Updated [project.yml](project.yml) (`CFBundleShortVersionString`, `CFBundleVersion`)
- Release zip `Release/HeartBit-v<version>.zip` and matching [Casks/heartbit.rb](Casks/heartbit.rb)
- Git commit + tag `v<version>` + push
- **GitHub Release** with notes (auto from `git log` since the previous tag, plus install blurb)

## Primary automation

Run from the repo root (macOS, Xcode + XcodeGen + `gh` authenticated):

```bash
./scripts/publish_release.sh <version>              # build number = previous + 1
./scripts/publish_release.sh <version> <build>    # explicit CFBundleVersion
./scripts/publish_release.sh --dry-run <version>   # preview only; no file/git/gh changes
```

Flags: `--no-push`, `--no-github`, `--skip-build` (expects zip already present), `--allow-dirty`.

**Human checkpoint:** use `--dry-run` first to review the release-notes preview, then run without it.

## Before publishing

1. **Merge or commit** all feature work; working tree should be clean (unless `--allow-dirty`).
2. **Smoke test** the app: `./scripts/build.sh dev` (Debug build + opens `HeartBit.app`).
3. **Auth:** `gh auth login` with permission to create releases on `ivans3m/homebrew-HeartBit`.
4. **Optional:** `brew` in PATH so the script can `brew audit --cask heartbit` after tapping this repo.

## If something fails

- **`brew audit`:** fix [Casks/heartbit.rb](Casks/heartbit.rb) or tap wiring; ensure `brew tap ivans3m/heartbit "$(pwd)"` works from the repo root.
- **`gh release create`:** if push succeeded but GitHub failed, create the release manually and attach `Release/HeartBit-v<version>.zip`, using the same notes format as the script (Changes + Install + macOS 14+).
- **Wrong version in YAML:** edit [project.yml](project.yml) carefully; re-run `scripts/build.sh release` and update the cask `version` / `sha256` to match the new zip.

## Related files

- [scripts/build.sh](scripts/build.sh) — `dev` vs `release`
- [scripts/publish_release.sh](scripts/publish_release.sh) — full publish pipeline
- [scripts/build_release.sh](scripts/build_release.sh) — wrapper calling `build.sh release`

## Out of scope here

Notarization/stapling, CI workflows, and Sparkle are separate follow-ups.
