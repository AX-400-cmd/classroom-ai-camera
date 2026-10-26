"""手机 APP 可调用的本地设备 API。

启动后，Flutter/Android 客户端通过 HTTP 调用这些接口；视频预览仍使用
Web/MJPEG，后续可替换为 WebRTC。
"""

import argparse
import json
import os
from http import HTTPStatus
from http.server import ThreadingHTTPServer
from pathlib import Path

from .behavior import BehaviorConfig
from .ptz import PTZConfig
from .web import CameraService, make_handler


def main():
    parser = argparse.ArgumentParser(description="智能课堂 AI 摄像头 APP API")
    parser.add_argument("--source", default="0")
    parser.add_argument("--output", default="outputs")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--fourcc", default="auto",
                        help="录制编码：auto 自动探测浏览器可播的编码器，或指定 avc1/H264/VP80/mp4v")
    parser.add_argument("--ptz-backend", default="none", choices=["none", "onvif"])
    parser.add_argument("--ptz-host", default="")
    parser.add_argument("--ptz-port", type=int, default=80)
    parser.add_argument("--ptz-user", default="")
    parser.add_argument("--ptz-password", default="")
    # ---- 摄像头分辨率（0=不改；行为检测建议 1280x720）----
    parser.add_argument("--camera-width", type=int, default=0)
    parser.add_argument("--camera-height", type=int, default=0)
    # ---- 行为检测：不加 --behavior 就完全不启用 ----
    parser.add_argument("--behavior", action="store_true",
                        help="启用课堂行为检测（玩手机/打瞌睡），默认关闭")
    parser.add_argument("--behavior-infer-fps", type=float, default=3.0)
    parser.add_argument("--behavior-imgsz", type=int, default=640)
    parser.add_argument("--behavior-model-dir", default="",
                        help="权重目录，放 yolov8n.pt 与 yolov8n-pose.pt")
    parser.add_argument("--behavior-person-conf", type=float, default=0.45)
    parser.add_argument("--behavior-phone-conf", type=float, default=0.30)
    parser.add_argument("--behavior-phone-hold", type=float, default=3.0,
                        help="玩手机持续多少秒判定")
    parser.add_argument("--behavior-sleep-hold", type=float, default=3.0,
                        help="打瞌睡持续多少秒判定（误报多可调到 4~5）")
    parser.add_argument("--behavior-cooldown", type=float, default=60.0)
    parser.add_argument("--behavior-max-tracks", type=int, default=20)
    parser.add_argument("--behavior-pose-stride", type=int, default=1,
                        help=">1 时跳帧推理，省 CPU（打瞌睡变化慢，2 足够）")
    parser.add_argument("--behavior-no-snapshot", action="store_true",
                        help="不保存告警留证截图")
    parser.add_argument("--behavior-debug", action="store_true",
                        help="打印每人姿态指标，用于现场标定阈值")
    parser.add_argument("--wx-config", default="",
                        help="微信小程序推送配置 wechat.json 的路径；不填则不启用微信推送")
    parser.add_argument("--api-token", default="",
                        help="接口访问令牌。配置后所有接口（除 /healthz）都需携带 "
                             "Authorization: Bearer <token> 或 ?token=<token>；"
                             "留空则不鉴权（仅局域网自用）。也可用环境变量 "
                             "CLASSROOM_API_TOKEN 注入，避免密钥出现在命令行里")
    args = parser.parse_args()

    # 环境变量优先级低于显式参数，但高于"完全不设"，方便服务化部署时注入
    api_token = (args.api_token or os.environ.get("CLASSROOM_API_TOKEN", "")).strip()

    # 相对路径在不同 cwd 下会指向不同目录，统一解析成绝对路径，
    # 否则 /files 列表可能返回空。
    args.output = str(Path(args.output).resolve())

    config = PTZConfig(
        enabled=args.ptz_backend != "none",
        backend=args.ptz_backend,
        host=args.ptz_host,
        port=args.ptz_port,
        username=args.ptz_user,
        password=args.ptz_password,
    )
    behavior = BehaviorConfig(
        enabled=args.behavior,
        infer_fps=args.behavior_infer_fps,
        imgsz=args.behavior_imgsz,
        model_dir=args.behavior_model_dir,
        person_conf=args.behavior_person_conf,
        phone_conf=args.behavior_phone_conf,
        phone_hold=args.behavior_phone_hold,
        sleep_hold=args.behavior_sleep_hold,
        cooldown=args.behavior_cooldown,
        max_tracks=args.behavior_max_tracks,
        pose_stride=args.behavior_pose_stride,
        save_snapshot=not args.behavior_no_snapshot,
        debug=args.behavior_debug,
    )
    service = CameraService(args.source, args.output, config, fourcc=args.fourcc,
                            behavior=behavior,
                            camera_size=(args.camera_width, args.camera_height),
                            wx_config=args.wx_config)
    service.start()
    server = ThreadingHTTPServer((args.host, args.port),
                                 make_handler(service, api_token=api_token))
    print(f"APP API 已启动：http://127.0.0.1:{args.port}")
    print("局域网 APP 请使用电脑 IP 访问，例如：http://192.168.1.10:8765")
    print(f"录制输出目录：{args.output}")
    print(f"录制编码：{service.record_codec}（容器 {service.record_ext}）")
    if api_token:
        print("接口鉴权：已开启（客户端需带 Authorization: Bearer <token> 或 ?token=）")
    else:
        print("接口鉴权：未开启 —— 任何能访问该地址的人都可查看画面与删除数据，"
              "仅可用于受信任的局域网")
    if behavior.enabled:
        print(f"行为检测：已启用（推理 {behavior.infer_fps}fps，"
              f"手机持续 {behavior.phone_hold}s / 瞌睡 {behavior.sleep_hold}s，"
              f"冷却 {behavior.cooldown}s）")
    if args.wx_config:
        wx = service.wx.status()
        if wx["active"]:
            print(f"微信订阅消息：已启用（订阅者 {wx['subscribers']} 人，"
                  f"剩余额度 {wx['quota_total']} 条，冷却 {args.behavior_cooldown}s 以上按配置）")
        else:
            print(f"微信订阅消息：未生效（enabled={wx['enabled']}，"
                  f"配置完整={wx['configured']}）— 检查 {args.wx_config}")
    try:
        server.serve_forever()
    finally:
        service.stop()


if __name__ == "__main__":
    main()
