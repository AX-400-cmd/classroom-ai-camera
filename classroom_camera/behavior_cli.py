"""行为检测离线标定工具（不改服务端，直接开摄像头跑）。

用法（本机必须用 py -3.12）：

    py -3.12 -m classroom_camera.behavior_cli --source 0 --show --seconds 120 --debug
        --behavior-model-dir "D:\\项目\\Claw\\ban\\models"

标定流程：让一个人依次做四个动作，每个约 30 秒，观察终端输出：
    1) 坐直听讲   2) 低头写字   3) 趴桌瞌睡   4) 举手机看
记录每种动作下 head_rel / drop / aspect / move 的分布，回填
`behavior.py` 的 BehaviorConfig 默认值（head_rel / drop / aspect_sleep /
head_move / phone_near_ratio）。

窗口里按 ESC 提前结束。cv2.putText 不支持中文，画面标签一律英文。
"""

from __future__ import annotations

import argparse
import queue
import time

import cv2

from .behavior import BehaviorConfig, BehaviorDetector
from .capture import CameraCapture


def _draw(image, track, cfg) -> None:
    x, y, w, h = (int(v) for v in track.box)
    color = (90, 200, 90)                       # 默认绿色：正常
    label = f"t{track.tid}"
    if track.phone_flag:
        color = (0, 140, 255)
        label = f"t{track.tid} PHONE {track.phone_sec:.1f}s"
    elif track.sleep_flag:
        color = (60, 60, 235)
        label = f"t{track.tid} SLEEP {track.sleep_sec:.1f}s"
    cv2.rectangle(image, (x, y), (x + w, y + h), color, 2)
    cv2.putText(image, label, (x, max(20, y - 6)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)
    # 姿态指标（纯 ASCII，cv2 画中文会出 ??）
    metrics = f"p{track.phone_sec:.1f} s{track.sleep_sec:.1f}"
    cv2.putText(image, metrics, (x, min(image.shape[0] - 6, y + h + 18)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)


def main() -> None:
    parser = argparse.ArgumentParser(description="课堂行为检测标定工具")
    parser.add_argument("--source", default="0")
    parser.add_argument("--output", default="outputs")
    parser.add_argument("--behavior-model-dir", default="")
    parser.add_argument("--infer-fps", type=float, default=3.0)
    parser.add_argument("--camera-width", type=int, default=0)
    parser.add_argument("--camera-height", type=int, default=0)
    parser.add_argument("--phone-hold", type=float, default=3.0)
    parser.add_argument("--sleep-hold", type=float, default=3.0)
    parser.add_argument("--seconds", type=float, default=0, help="0=一直跑到按 ESC")
    parser.add_argument("--show", action="store_true", help="显示画面窗口")
    parser.add_argument("--debug", action="store_true", help="打印每人姿态指标")
    args = parser.parse_args()

    cfg = BehaviorConfig(
        enabled=True,
        model_dir=args.behavior_model_dir,
        infer_fps=args.infer_fps,
        phone_hold=args.phone_hold,
        sleep_hold=args.sleep_hold,
        debug=args.debug,
        save_snapshot=False,          # 标定阶段不存图
    )
    detector = BehaviorDetector(args.output, cfg, queue.Queue(maxsize=1))
    print("正在加载模型（首次较慢）...")
    try:
        detector.load()
    except Exception as exc:
        print(f"模型加载失败：{exc}")
        print("请先完成 M1：安装 torch/ultralytics 并下载权重到 --behavior-model-dir")
        return
    print("模型就绪。按 ESC 结束。")

    camera = CameraCapture(args.source, args.output,
                           width=args.camera_width, height=args.camera_height)
    camera.open()
    end_at = time.time() + args.seconds if args.seconds > 0 else None
    last = 0.0
    try:
        while True:
            if end_at is not None and time.time() > end_at:
                break
            ok, frame = camera.read()
            if not ok or frame is None:
                time.sleep(0.05)
                continue
            now = time.time()
            if now - last < 1.0 / max(cfg.infer_fps, 0.1):
                if args.show:
                    cv2.imshow("Behavior Debug", frame)
                    if cv2.waitKey(1) & 0xFF == 27:
                        break
                continue
            last = now
            detector.process_frame(frame)
            snap = detector.snapshot
            if args.show:
                shown = frame.copy()
                for tr in detector.tracks:
                    _draw(shown, tr, cfg)
                cv2.putText(shown, f"persons={snap.persons} phone={snap.phone_now} "
                                   f"sleep={snap.sleep_now} {snap.infer_ms:.0f}ms",
                            (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
                cv2.imshow("Behavior Debug", shown)
                if cv2.waitKey(1) & 0xFF == 27:
                    break
    finally:
        camera.close()
        if args.show:
            cv2.destroyAllWindows()
    print(f"结束。共产生 {len(detector.snapshot.alerts)} 条告警。")


if __name__ == "__main__":
    main()
