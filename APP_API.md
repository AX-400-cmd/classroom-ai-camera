# APP 接入说明

Python 服务作为边缘设备 API，Flutter APP 通过 HTTP 调用它。

## 启动

```powershell
py -3.12 -m classroom_camera.api_server --source 0 --host 0.0.0.0
```

常用参数：

| 参数                                                | 默认            | 说明                                     |
| ------------------------------------------------- | ------------- | -------------------------------------- |
| `--host`                                          | `0.0.0.0`     | 监听地址                                   |
| `--port`                                          | `8765`        | 端口                                     |
| `--source`                                        | `0`           | 摄像头索引或 RTSP/视频文件地址                     |
| `--output`                                        | `outputs`     | 录制与截图输出目录（会解析为绝对路径）                    |
| `--fourcc`                                        | 自动探测          | 录制编码器，优先选 `avc1`（H.264），回退 `mp4v`      |
| `--camera-width` / `--camera-height`              | `0`（不改）       | 摄像头分辨率；行为检测建议 `1280` / `720`           |
| `--behavior`                                      | 关闭            | **启用课堂行为检测**（玩手机 / 打瞌睡），不加就完全不加载模型     |
| `--behavior-model-dir`                            | 空             | 权重目录（`yolov8n.pt` + `yolov8n-pose.pt`） |
| `--behavior-infer-fps`                            | `3.0`         | 抽样推理帧率，CPU 吃紧降到 2                      |
| `--behavior-phone-hold` / `--behavior-sleep-hold` | `3.0` / `3.0` | 持续多少秒判定（瞌睡误报多可把 sleep 调到 4~5）          |
| `--behavior-cooldown`                             | `60`          | 同一人同类告警冷却秒数                            |
| `--behavior-pose-stride`                          | `1`           | `2` = 跳帧推理，省约 35% CPU                  |
| `--behavior-no-snapshot`                          | 关闭            | 不保存告警留证截图                              |
| `--behavior-debug`                                | 关闭            | 打印每人姿态指标，用于现场标定                        |

手机与电脑连接同一 Wi-Fi 后，使用电脑局域网 IP：

```text
http://电脑IP:8765
```

## 跨域（CORS）

浏览器（含 Flutter Web）访问局域网 IP 会被同源策略拦截，后端已统一处理：

- 所有响应带 `Access-Control-Allow-Origin: *`
- OPTIONS 预flight 返回 `204`，并带 `Access-Control-Allow-Private-Network: true`  
  （Chrome 从 localhost 访问 `192.168.x.x` 属于私有网络访问，缺这个头会被拦）
- 自定义响应头通过 `Access-Control-Expose-Headers` 暴露，前端才能读到
- 错误响应也必须带 CORS 头，因此统一走 `_error()`，不用 `send_error()`

## 接口

| 方法   | 地址                                 | 作用                                      |
| ---- | ---------------------------------- | --------------------------------------- |
| GET  | `/status`                          | 设备、录制、跟踪、云台状态                           |
| GET  | `/frame.jpg`                       | 单帧 JPEG；`?raw=1` 取未叠加目标框的原始帧            |
| GET  | `/video_feed`                      | MJPEG 实时预览                              |
| POST | `/start`                           | 开始录制                                    |
| POST | `/stop`                            | 停止录制                                    |
| POST | `/snapshot`                        | 保存截图                                    |
| POST | `/select_target`                   | JSON `{"x":0.5,"y":0.5}` 选择教师           |
| POST | `/clear_target`                    | 清除跟踪目标                                  |
| GET  | `/files`                           | 录制文件列表                                  |
| GET  | `/files/download?name=xxx.mp4`     | 下载/播放，支持 HTTP Range（206）                |
| GET  | `/files/poster?name=xxx.mp4`       | 视频封面帧                                   |
| POST | `/files/delete`                    | JSON `{"name":"xxx.mp4"}` 删除文件          |
| GET  | `/alerts`                          | 行为告警列表，`?since=a0007&limit=50` 增量拉取     |
| POST | `/alerts/clear`                    | 清空告警记录                                  |
| POST | `/alerts/test`                     | JSON `{"kind":"phone"}` 造一条测试告警（验证通知链路） |
| POST | `/behavior/start` `/behavior/stop` | 运行中热开关行为检测                              |

### `/status` 返回字段

```json
{
  "recording": false,
  "recording_path": "",
  "target_status": "跟踪中",
  "target_box": [289, 30, 160, 240],
  "ptz_status": "未启用",
  "frame_width": 640,
  "frame_height": 480,
  "target_status_code": "tracking",
  "recording_name": "",
  "record_codec": "avc1",
  "output_dir": "D:\\outputs",
  "server_time": 1790685506.07
}
```

`frame_width` / `frame_height` 是画目标框的必要输入：APP 端按 `BoxFit.contain`  
的 letterbox 换算后才能把像素框映射到屏幕坐标。

### `/frame.jpg` 响应头

| 头                                  | 说明                      |
| ---------------------------------- | ----------------------- |
| `X-Frame-Width` / `X-Frame-Height` | 当前帧分辨率                  |
| `X-Target-Box`                     | `x,y,w,h`，未选择目标时为 `-`   |
| `X-Target-Status`                  | `tracking` / `lost` / 空 |

目标框信息与这一帧严格同步，比 `/status` 轮询少一帧延迟。

### `/files` 返回字段

```json
{
  "ok": true,
  "output_dir": "D:\\outputs",
  "files": [
    {
      "name": "class_20260929_200359.mp4",
      "kind": "video",
      "size": 2516286,
      "mtime": 1790683443,
      "modified": "2026-09-29 20:04:03",
      "recording": false,
      "url": "/files/download?name=class_20260929_200359.mp4",
      "poster": "/files/poster?name=class_20260929_200359.mp4"
    }
  ]
}
```

`recording: true` 表示该文件正在写入，APP 会禁用删除按钮。

### `/alerts` 返回字段

```json
{
  "ok": true,
  "server_time": 1790685506.07,
  "enabled": true,
  "running": true,
  "error": "",
  "last_id": "a0012",
  "alerts": [
    {
      "id": "a0012",
      "kind": "phone",
      "track_id": 3,
      "ts": 1790685488.42,
      "time": "2026-09-30 20:38:08",
      "seconds": 3.4,
      "box": [289, 30, 160, 240],
      "score": 0.82,
      "evidence": "手机框在人物上半身，距手腕/头部 0.11×身高",
      "snapshot": "alert_20260930_203808_t3_phone.jpg",
      "snapshot_url": "/files/download?name=alert_20260930_203808_t3_phone.jpg"
    }
  ]
}
```

- `since` 为空返回全部（受后端 `history=200` 上限），否则只返回 `id` 更大的部分；  
  `id` 形如 `a0001`，字典序即时间序，可直接当游标。
- `box` 是**帧像素**坐标，`snapshot` 为留证截图文件名（纯 ASCII，可直接走 `/files/download`）。

### `/status` 新增的行为检测字段

```json
{
  "behavior_enabled": true,
  "behavior_running": true,
  "behavior_error": "",
  "behavior_persons": 6,
  "behavior_phone": 1,
  "behavior_sleep": 0,
  "behavior_boxes": [[289, 30, 160, 240, "phone", 0.82]],
  "alert_count": 12,
  "alert_last_id": "a0012",
  "alert_last_ts": 1790685488.42,
  "alert_last_kind": "phone"
}
```

`behavior_boxes` 元素为 `[x, y, w, h, kind, score]`：APP 默认取 `?raw=1` 原始帧并自己  
画框，服务端叠加在 `jpeg` 上的框 APP 看不到，所以必须走这个字段。

## 行为检测（玩手机 / 打瞌睡）

### 依赖与模型

```powershell
# 必须用 py -3.12（默认的 python 是另一个空环境）
py -3.12 -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
py -3.12 -m pip install ultralytics --no-deps      # ★ 防止把 OpenCV 5.0 降到 4.x
py -3.12 -m pip install pyyaml requests tqdm psutil
py -3.12 -c "import cv2; print(cv2.__version__)"   # 必须还是 5.0.0
```

权重放 `D:\项目\Claw\ban\models\`：`yolov8n.pt`（6.2MB）、`yolov8n-pose.pt`（6.5MB），  
启动时用 `--behavior-model-dir` 指定。

### 判据与阈值（都在 `behavior.py` 的 `BehaviorConfig`）

| 行为      | 判据                                                                      | 默认      |
| ------- | ----------------------------------------------------------------------- | ------- |
| 玩手机（主）  | phone 框中心落在人物框内，且到手腕/鼻尖距离 ÷ 框高 ≤ 阈值                                     | `0.22`  |
| 玩手机（兜底） | 检不到手机框时：手腕贴近头部 ≤ `0.20` × 框高，且只对框高 ≥ 80px 启用                            | 开       |
| 打瞌睡     | 三选二：`head_rel ≥ 0.28`（头部偏低）、`drop ≥ -0.12`（鼻尖接近肩线）、`aspect ≥ 0.60`（框变宽） | votes=2 |
| 打瞌睡静止项  | 头部位移速度 ≤ `0.05` × 框高/秒（区分「瞌睡」与「低头写字」的关键）                                | 开       |

姿态模型没有眼睑信息，所以「打瞌睡」判的是**低头 + 长时间不动**，不是真的眼皮闭合。

### 现场标定（强烈建议）

```powershell
py -3.12 -m classroom_camera.behavior_cli --source 0 --show --seconds 120 --debug `
    --behavior-model-dir "D:\项目\Claw\ban\models"
```

让一个人依次做：坐直听讲 → 低头写字 → 趴桌瞌睡 → 举手机看（各 30 秒），  
看终端打印的 `head_rel / drop / aspect / move`，回填 `BehaviorConfig` 默认值。

### 已知限制

- 640×480 下 6 米外的学生手机框基本检不到，只能靠手腕贴脸兜底；建议设 1280×720，  
  摄像头装在**前侧上方 45° 俯视**（看不到桌面就检不到手机）。
- 「打瞌睡」与「低头写字」天然难分，误报率预计 10–30%，需现场标定并调 `sleep_hold`。
- 推理 150–270ms/帧 @3fps，约占单核 40–80%；吃紧时降 `--behavior-infer-fps 2`  
  或 `--behavior-pose-stride 2`。
- **隐私**：只保存告警瞬间截图，通知里不含姓名（只有 `track_id`）；正式使用前  
  应取得学校/家长知情同意。

## 安全

`name` 参数经过三重校验后才拼接路径：拒绝 `/`、`\`、空字节、`..`，后缀必须在白名单内，  
且 `resolve()` 之后必须仍在输出目录之内。非法文件名一律返回 `404`。

## 已知坑

- OpenCV 在 Windows 上对**含中文的路径**有 bug：`VideoWriter` 与 `imwrite` 会静默失败，  
  `VideoCapture` 读取正常。规避办法是用 `os.chdir()` 切到目标目录后只传文件名  
  （见 `capture.py` 的 `open_video_writer` / `imwrite_safe`）。
- `mp4v` 写出的是 MPEG-4 Part 2（FMP4），**Chrome 无法播放**。用 `avc1` 才是真 H.264。  
  启动时会自动探测可用编码器。
- Chrome 的 `<video>` 拖拽进度条依赖 HTTP Range，必须返回 `206` 并带 `Accept-Ranges`。

## 当前阶段

- 支持浏览器、Flutter Web、Android 调用
- 视频预览用 MJPEG，开发验证简单
- 录制用 H.264/MP4，浏览器可直接播放
- 正式部署建议换成 WebRTC，并增加登录鉴权
