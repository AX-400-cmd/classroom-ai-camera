# 智能课堂 AI 摄像头系统 v1.0.0

首个公开版本。基于 YOLOv8 的课堂行为分析：实时检测学生玩手机 / 打瞌睡，支持实时预览、告警留证，并提供 Flutter 安卓 APP 与微信小程序两种客户端。

## 功能特性

- **行为检测**：YOLOv8 + 目标跟踪，检测玩手机、打瞌睡（趴桌 / 低头）
- **实时预览与录制**：APP 端查看摄像头画面，可按需录制课堂视频
- **告警留证**：检测到异常自动截图留证，可选通过微信订阅消息推送到教师手机
- **课堂统计**：注意力、告警次数等数据落库，APP 端以图表可视化
- **多摄像头接入**：后端 `--source` 切换不同摄像头 / RTSP / GB28181 视频源
- **令牌鉴权**：支持 `Authorization: Bearer` 与 `?token=`，适合校内 / 自托管部署

## 本发行版包含

- 已编译的安卓安装包（arm64-v8a / armeabi-v7a / x86_64），**直接安装即可，无需本地构建**
- Python 后端、Flutter APP 源码、微信小程序源码均在仓库中

## 系统要求

- **后端**：Python 3.9+，带摄像头的电脑，或 RTSP / GB28181 视频源
- **APP**：Android 6.0+（arm64 机型请安装 `app-arm64-v8a-release.apk`）
- **微信小程序**：需自行配置 AppID 与订阅消息模板

## 快速开始

1. 安装后端依赖：`pip install -r requirements.txt`
2. 启动后端：`python -m classroom_camera.api_server --source 0`（摄像头编号按需替换）
3. 手机安装本发行版 APK，地址栏填入电脑内网 IP（如 `http://192.168.x.x:8000`）；若后端设置了 `CLASSROOM_API_TOKEN`，令牌栏填相同的值。

## 已知问题

- 本地从中文路径打包 APP 需使用 `build_android.bat`（已做虚拟盘映射），或直接下载本发行版 APK。
- 微信推送需自行在微信公众平台申请订阅消息模板，并参考 `wechat.example.json` 配置 `wechat.json`。
- `outputs/`（真实课堂录像 / 截图 / 统计库）与 `work/`（个人文档）已默认排除在仓库之外。

## 许可证

MIT —— 详见 [LICENSE](LICENSE)。
