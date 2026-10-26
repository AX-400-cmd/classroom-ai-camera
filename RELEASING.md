# Release Process

This project uses **tag-triggered automated releases**. You do not build the APK
locally — GitHub Actions does it for you.

## How it works

1. The workflow `.github/workflows/build-and-release.yml` runs on every push of a
   tag matching `v*`.
2. It builds the Flutter app on `ubuntu-latest` (Flutter **3.47.5**, pinned to
   match the local dev environment) with `flutter build apk --release
   --split-per-abi`.
3. It creates a GitHub Release named after the tag, attaches the three ABI APKs,
   and uses `RELEASE_NOTES.md` as the release body.

> Building on CI avoids the local Chinese-path `gradlew` issue entirely, because
> Linux paths are ASCII.

## Steps to cut a release

```powershell
cd D:\智能课堂摄像头系统

# 1. Make sure main is up to date and the build is green
git checkout main
git pull

# 2. (Optional) update RELEASE_NOTES.md and CHANGELOG.md, then commit + push
git add -A
git commit -m "docs: prepare v1.1.0 release notes"
git push origin main

# 3. Tag and push the tag — this triggers the build & release
git tag v1.1.0
git push origin v1.1.0
```

4. Watch **Actions → Build & Release APK**. When it finishes, the new Release
   (with APKs) appears under **Releases**.

## Rules

- **Tag format**: `vMAJOR.MINOR.PATCH` (e.g. `v1.0.0`). Only `v*` tags trigger
  the release workflow.
- **Never commit secrets** (`wechat.json`, `*.db`, tokens). They are git-ignored.
- **Model weights**: keep `models/` in the repo; do not replace them with
  proprietary files without checking the Ultralytics license.
- **Re-running a failed tag run is not enough** — the workflow file is read from
  the tagged commit. If you fix the workflow, delete the old tag, push the fix to
  `main`, then re-tag on the new commit.

## Rollback

Tags are immutable in spirit; to "undo" a release, delete the tag and the GitHub
Release, fix the issue, and cut a new patch tag (e.g. `v1.0.1`).
