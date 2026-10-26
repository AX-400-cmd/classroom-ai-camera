# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-26

First public release.

### Added

- **Behavior detection**: YOLOv8 + tracking for phone use and dozing off.
- **Live preview & recording**: web preview plus local MP4 recording.
- **Alert evidence**: frames are captured on detection for later review.
- **Multi-client**: Flutter Android app and WeChat mini-program.
- **WeChat notifications** (optional): alert push via subscribe messages.
- **Statistics**: attention duration and alert counts stored in SQLite and
  visualized in the app.
- **ONVIF PTZ** (optional): auto-pan for ONVIF-capable cameras.
- **Authentication**: `Authorization: Bearer` / `?token=` token support for
  safe self-hosting.
- **Windows unattended tooling**: watchdog, cleanup, and auto-start scripts.
- **CI**: GitHub Actions workflow that builds and publishes release APKs on tag.
- **Docs**: bilingual README, GitHub Pages site, issue/PR templates, security and
  code-of-conduct policies, contributing guide.

### Notes

- The `models/` YOLOv8 weights ship with the repository (Ultralytics license).
- `outputs/` (real classroom footage) and `work/` (personal documents) are
  intentionally excluded from the repository for privacy.

[1.0.0]: https://github.com/AX-400-cmd/classroom-ai-camera/releases/tag/v1.0.0
