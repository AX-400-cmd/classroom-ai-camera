# Getting Started (English)

This guide helps you run the Intelligent Classroom AI Camera System on your own
machine. It is meant to be copied into the GitHub Wiki as the "Quick Start" page.

## What you need

- A computer with a webcam (or an RTSP / GB28181 / ONVIF camera)
- Python **3.12+**
- For the mobile app: Flutter **3.47.5+** and the Android SDK
- For the mini-program: WeChat DevTools

## 1. Start the Python backend

```bash
cd classroom_camera
python -m venv .venv
source .venv/bin/activate        # Windows: .\.venv\Scripts\Activate.ps1
pip install -r ../requirements.txt
python -m classroom_camera.api_server --source 0 --host 0.0.0.0
```

- Web preview: <http://127.0.0.1:8765>
- API reference: [`APP_API.md`](../APP_API.md)
- Replace `--source 0` with a camera index, an RTSP URL, or a video file.

## 2. Enable authentication (recommended)

Set a token so the service is not open to everyone on your network:

```bash
export CLASSROOM_API_TOKEN="your-strong-token"   # Windows: set CLASSROOM_API_TOKEN=...
```

Then enter the same token in the Flutter app / mini-program when connecting.

## 3. Connect a client

- **Flutter app**: `flutter pub get` then `flutter run` (Android). To build a
  release APK, see [`BUILD_ANDROID.md`](../BUILD_ANDROID.md), or download a
  prebuilt APK from the [Releases](https://github.com/AX-400-cmd/classroom-ai-camera/releases)
  page.
- **WeChat mini-program**: import `wechat_mini/` in WeChat DevTools and set the
  backend URL + token in the settings page.

## 4. WeChat notifications (optional)

Copy `wechat.example.json` to `wechat.json`, or inject the values via environment
variables `WECHAT_APPID` / `WECHAT_APPSECRET` / `WECHAT_TEMPLATE_ID`.

> ⚠️ Never commit `wechat.json` or any real secret. They are excluded by
> `.gitignore`.

## 5. Run unattended (Windows)

The `deploy/` folder contains a watchdog, a cleanup script, and an auto-start
helper. See [`work/上线部署方案.md`](../work/) for the full self-hosting guide
(note: the `work/` folder is kept local and not pushed to the repository).

## Troubleshooting

- **Build fails with a Dart version error** — make sure your local Flutter
  matches `3.47.5` (or newer). CI uses the same version.
- **App cannot connect** — verify the backend `--host 0.0.0.0` is reachable on
  the LAN and that the token (if set) matches.
- **No notifications** — confirm the WeChat subscribe-message template is
  approved and the user has subscribed.
