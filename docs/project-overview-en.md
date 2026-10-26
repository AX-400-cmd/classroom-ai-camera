# Project Overview (English)

> Copy this page into the GitHub Wiki as the project home, or use the long
> description below for the repository "About" section.

**Intelligent Classroom AI Camera System** is an open-source classroom
behavior-analysis toolkit built around YOLOv8. It runs on a normal PC with a
webcam (or any RTSP / GB28181 / ONVIF camera) and helps teachers spot
attention-distracting behaviors in real time — primarily **phone use** and
**dozing off** — without sending anything to the cloud by default.

## Why this project exists

Manual classroom monitoring does not scale. This project turns a single camera
into a privacy-respecting助教 that:

- detects distraction behaviors with a lightweight YOLOv8 model,
- shows a live preview and records evidence locally,
- pushes optional WeChat alerts to the teacher's phone,
- and produces attention / alert statistics for after-class review.

## Highlights

- **Edge-first & private**: everything runs locally; alert evidence is stored on
  disk only, and secrets live in environment variables.
- **Multi-client**: a Flutter Android app and a WeChat mini-program share the
  same backend.
- **Self-hostable**: token auth, Windows unattended scripts, and a clear
  deployment guide.
- **Ready to build**: prebuilt APKs are attached to every release, and CI builds
  them automatically on tag.

## Tech stack

| Layer | Technology |
| --- | --- |
| Detection | YOLOv8 (Ultralytics) + OpenCV, ByteTrack-style tracking |
| Backend | Python 3.12, ThreadingHTTPServer, SQLite |
| Mobile | Flutter 3.47.5 (Android) |
| Mini-program | WeChat WXML / WXSS |
| Notifications | WeChat subscribe messages |
| CI / Release | GitHub Actions (auto-build APK on tag) |

## Long description (for GitHub "About")

> YOLOv8-based classroom behavior analysis: real-time phone/sleep detection,
> live preview, local alert evidence, with a Flutter Android app and a WeChat
> mini-program. Privacy-first, self-hostable, MIT licensed.

## Suggested topics

`yolov8`, `classroom`, `behavior-detection`, `computer-vision`,
`object-detection`, `flutter`, `wechat-miniprogram`, `education`, `python`, `ai`
