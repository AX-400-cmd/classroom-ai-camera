# 智能课堂 AI 摄像头系统

基于 YOLOv8 的课堂学生行为分析系统：检测「玩手机 / 打瞌睡」等注意力分散行为，支持实时预览、本地录制、告警留证，并提供 Flutter 手机端、微信小程序、微信通知与统计报表。

> 面向教育场景的行为分析 Demo / 课程设计 / 毕业设计。注重隐私合规：默认不暴露公网，告警留证仅存本地，敏感配置走环境变量。

## 功能特性

- **行为检测**：玩手机、打瞌睡（基于 YOLOv8 目标 / 姿态检测）
- **实时预览与本地录制**：浏览器 Web 端 + MP4 落盘
- **告警留证**：命中即截帧保存，可回溯核查
- **多端查看**：Flutter Android APP、微信小程序
- **微信通知**（可选）：订阅消息推送告警
- **统计报表**：注意力时长、告警次数等落库与可视化
- **ONVIF 云台**（可选）：支持 ONVIF 的摄像头可自动转向

## 架构

| 目录 | 说明 |
| --- | --- |
| `classroom_camera/` | Python 后端：检测、跟踪、Web/API 服务、微信推送、统计 |
| `flutter_app/` | Flutter 安卓端：预览 / 录制 / 告警 / 统计 |
| `wechat_mini/` | 微信小程序端 |
| `deploy/` | Windows 无人值守：看门狗、清理、开机自启 |
| `models/` | YOLOv8 权重（来自 Ultralytics） |

## 快速开始

### 1. 后端（Python，需 3.12）

```powershell
cd classroom_camera
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r ../requirements.txt
python -m classroom_camera.api_server --source 0 --host 0.0.0.0
```

Web 预览地址：`http://127.0.0.1:8765`
接口说明见 [`APP_API.md`](./APP_API.md)。

### 2. 鉴权（建议开启）

设置环境变量 `CLASSROOM_API_TOKEN`，并在 APP / 小程序连接时填入相同令牌，避免服务被未授权访问。

### 3. 手机端 / 小程序

- **Flutter**：`flutter pub get` 后 `flutter run`（安卓）；打包见 [`BUILD_ANDROID.md`](./BUILD_ANDROID.md)。
- **小程序**：用微信开发者工具导入 `wechat_mini/`，在设置中填写后端地址与令牌。

### 4. 微信通知（可选）

复制 `wechat.example.json` 为 `wechat.json`，或用环境变量 `WECHAT_APPID` / `WECHAT_APP_SECRET` / `WECHAT_TEMPLATE_ID` 注入。**密钥请勿提交到仓库。**

## 模型权重许可

`models/` 下的 YOLOv8 权重来自 [Ultralytics](https://github.com/ultralytics/ultralytics)，遵循其许可协议。研究 / 非商业用途可直接使用；商业用途请另行获取授权。

## 许可证

本项目以 [MIT License](./LICENSE) 开源。社区规范见 [行为准则](./CODE_OF_CONDUCT.md) 与安全策略 [SECURITY.md](./SECURITY.md)。

---

# Intelligent Classroom AI Camera System

A YOLOv8-powered classroom student behavior analysis system. It detects attention-distracting behaviors such as **phone use** and **dozing off**, with live preview, local recording, alert evidence capture, plus a Flutter mobile app, a WeChat mini-program, WeChat notifications, and statistics dashboards.

> A behavior-analysis demo / course project / graduation project for educational scenarios. Privacy-first: not exposed to the public internet by default, alert evidence is stored locally only, and sensitive config is injected via environment variables.

## Features

- **Behavior detection**: phone use, dozing (based on YOLOv8 object / pose detection)
- **Live preview & local recording**: browser Web UI + MP4 output
- **Alert evidence**: frames are captured on detection for later review
- **Multi-platform clients**: Flutter Android app, WeChat mini-program
- **WeChat notifications** (optional): alert push via subscribe messages
- **Statistics dashboard**: attention duration, alert counts, etc.
- **ONVIF PTZ** (optional): auto-pan for ONVIF-capable cameras

## Architecture

| Directory | Description |
| --- | --- |
| `classroom_camera/` | Python backend: detection, tracking, Web/API service, WeChat push, stats |
| `flutter_app/` | Flutter Android app: preview / recording / alerts / stats |
| `wechat_mini/` | WeChat mini-program client |
| `deploy/` | Windows unattended tooling: watchdog, cleanup, auto-start |
| `models/` | YOLOv8 weights (from Ultralytics) |

## Quick Start

### 1. Backend (Python 3.12 required)

```powershell
cd classroom_camera
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r ../requirements.txt
python -m classroom_camera.api_server --source 0 --host 0.0.0.0
```

Web preview: `http://127.0.0.1:8765`
API reference: [`APP_API.md`](./APP_API.md).

### 2. Authentication (recommended)

Set the `CLASSROOM_API_TOKEN` environment variable and use the same token when connecting from the app / mini-program to prevent unauthorized access.

### 3. Mobile / Mini-program

- **Flutter**: `flutter pub get` then `flutter run` (Android); packaging see [`BUILD_ANDROID.md`](./BUILD_ANDROID.md).
- **Mini-program**: import `wechat_mini/` in WeChat DevTools and configure the backend URL and token in settings.

### 4. WeChat notifications (optional)

Copy `wechat.example.json` to `wechat.json`, or inject via env vars `WECHAT_APPID` / `WECHAT_APP_SECRET` / `WECHAT_TEMPLATE_ID`. **Do not commit secrets.**

## Model License

The YOLOv8 weights in `models/` come from [Ultralytics](https://github.com/ultralytics/ultralytics) and follow their license. Free for research / non-commercial use; obtain a separate license for commercial use.

## License

Released under the [MIT License](./LICENSE). Community standards: [Code of Conduct](./CODE_OF_CONDUCT.md) and [Security Policy](./SECURITY.md).
