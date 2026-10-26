"""课堂行为检测：玩手机 / 打瞌睡。

三条硬约束（改动时务必遵守）：
1. **绝不在采集线程里推理** —— web.py 的 `_loop` 整段持 `service.lock`，
   同步推理会卡死 `/status`（APP 端 5s 超时）与 `/frame.jpg`（4s 超时）。
   采集线程只做 `frame.copy()` 丢进队列，推理全部在独立 worker 线程里完成。
2. **结果用「构造不可变快照 → 单引用原子替换」回传**，读写双方都不加锁。
   不要引入第二把锁与 `service.lock` 嵌套（会死锁）。
3. **写截图一律走 `capture.imwrite_safe`** —— OpenCV 在中文路径下 `imwrite`
   会静默返回 False；文件名必须纯 ASCII，才能复用 `/files/download`。

依赖 torch / ultralytics 采用**延迟导入**：没装时服务照常启动，只是
`behavior_error` 里能读到原因。
"""

from __future__ import annotations

import math
import os
import queue
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import quote

import numpy as np

# COCO 17 关键点索引（YOLOv8-pose 输出顺序）
NOSE, L_EYE, R_EYE, L_EAR, R_EAR = 0, 1, 2, 3, 4
L_SHOULDER, R_SHOULDER = 5, 6
L_ELBOW, R_ELBOW = 7, 8
L_WRIST, R_WRIST = 9, 10
L_HIP, R_HIP = 11, 12

# 头部关键点（用于求头部质心）
_HEAD_IDS = (NOSE, L_EYE, R_EYE, L_EAR, R_EAR)


@dataclass
class BehaviorConfig:
    """行为检测配置。所有阈值都是「尺度无关」的（除以框高/框宽）。"""

    enabled: bool = False
    infer_fps: float = 3.0          # 抽样推理帧率
    imgsz: int = 640                # 模型输入尺寸（不必等于摄像头分辨率）
    model_dir: str = ""             # 权重目录；空则用 ultralytics 默认路径/下载

    person_conf: float = 0.45
    phone_conf: float = 0.30
    kp_conf: float = 0.50           # 关键点置信度下限
    min_person_h: int = 40          # 低于此高度的 person 框直接丢弃
    person_max_wh_ratio: float = 3.0  # 只拦极端异常框（真人近距离坐姿可达 1.5~2.0，
                                      # 别用宽度卡人；静物交给 kp_min_visible 过滤）
    fallback_min_h: int = 80        # 兜底判据 / 打瞌睡只对近处大目标启用

    iou_gate: float = 0.15          # IOU 匹配门限
    max_missed: int = 5             # 连续未匹配帧数上限（≈1.7s @3fps）
    max_age: float = 2.5            # 未匹配超过这么久就删除
    max_tracks: int = 20
    pose_stride: int = 1            # >1 时跳帧推理（沿用上一帧状态），省 CPU

    phone_hold: float = 3.0         # 玩手机持续多少秒判定
    sleep_hold: float = 3.0         # 打瞌睡持续多少秒判定（误报多可调到 4~5）
    reset_gap: float = 1.5          # 中断超过这么久才清零累计
    cooldown: float = 60.0          # 同一人同类告警冷却
    global_limit: int = 10          # 全局每分钟最多告警条数

    phone_near_ratio: float = 0.22  # 手机中心到手腕/鼻尖距离 / 框高
    phone_wrist_fallback: bool = True
    wrist_face_ratio: float = 0.20

    sleep_votes: int = 2            # 三选二
    head_rel: float = 0.28          # 头部质心相对框顶 / 框高
    drop: float = -0.12             # (鼻尖y - 肩中点y) / 框高
    aspect_sleep: float = 0.60      # 框宽高比下限（趴桌时变宽）
    aspect_max: float = 1.60        # 上限：再宽就不是人了
    kp_min_visible: int = 4         # 头肩关键点最少可见数（静物基本不达标）
    sleep_require_still: bool = True
    head_move: float = 0.05         # 头部位移速度 / 框高 / 秒

    save_snapshot: bool = True
    history: int = 200              # 最多保留多少条告警
    debug: bool = False


@dataclass
class AlertEvent:
    """一条行为告警。id 形如 a0001，字典序即时间序，APP 用它做增量游标。"""

    id: str
    kind: str                       # 统一为 "attention"（注意力不集中）
    track_id: int
    ts: float                       # epoch 秒
    seconds: float
    box: tuple[int, int, int, int]
    score: float
    evidence: str
    snapshot: str = ""              # 留证截图文件名（相对 output_dir）
    detail: str = "attention"       # 具体表现："phone" | "sleep" | "attention"

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "detail": self.detail,
            "track_id": self.track_id,
            "ts": self.ts,
            "time": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(self.ts)),
            "seconds": round(self.seconds, 1),
            "box": list(self.box),
            "score": round(self.score, 2),
            "evidence": self.evidence,
            "snapshot": self.snapshot,
            "snapshot_url": (
                f"/files/download?name={quote(self.snapshot)}" if self.snapshot else ""
            ),
        }


@dataclass(frozen=True)
class BehaviorSnapshot:
    """一次性整体替换的只读快照。

    写方（worker）整体构造后单次赋值给 `self.snapshot`，读方（采集线程画框、
    /status、/alerts）单次读取。CPython 下引用赋值是原子的，读到的永远是
    完整旧对象，不会撕裂，因此双方都不需要加锁。
    """

    running: bool = False
    error: str = ""
    infer_ms: float = 0.0
    persons: int = 0
    phone_now: int = 0
    sleep_now: int = 0
    boxes: tuple[tuple[int, int, int, int, str, float], ...] = ()  # x,y,w,h,kind,score
    alerts: tuple[AlertEvent, ...] = ()

    @property
    def last_id(self) -> str:
        return self.alerts[-1].id if self.alerts else ""


@dataclass
class Track:
    """一个人的跟踪状态。"""

    tid: int
    box: tuple[float, float, float, float]      # x, y, w, h（像素）
    kps: np.ndarray | None = None               # (17, 3)
    conf: float = 0.0
    hits: int = 0
    missed: int = 0
    confirmed: bool = False
    last_seen: float = 0.0
    head_hist: deque = field(default_factory=lambda: deque(maxlen=8))
    phone_sec: float = 0.0
    sleep_sec: float = 0.0
    phone_gap: float = 0.0
    sleep_gap: float = 0.0
    phone_flag: bool = False
    sleep_flag: bool = False
    phone_score: float = 0.0
    sleep_score: float = 0.0
    phone_evidence: str = ""
    sleep_evidence: str = ""
    last_alert: dict[str, float] = field(default_factory=dict)


class BehaviorDetector:
    """YOLOv8n 行为检测器（worker 线程 + 队列抽帧）。"""

    def __init__(self, output_dir: str, config: BehaviorConfig,
                 frame_queue: "queue.Queue[np.ndarray]"):
        self.output_dir = Path(output_dir)
        self.cfg = config
        self.q = frame_queue
        self.snapshot = BehaviorSnapshot()
        self._alerts: list[AlertEvent] = []
        self._tracks: list[Track] = []
        self._seq = 0
        self._tid = 0
        self._frame_index = 0
        self._last_ts = 0.0
        self._last_frame: np.ndarray | None = None
        self._minute: deque[float] = deque()
        self._thread: threading.Thread | None = None
        self._running = False
        self.det = None        # YOLOv8n detect（只检 cell phone）
        self.pose = None       # YOLOv8n pose（person + 17 关键点）

    # ==================== 生命周期 ====================
    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self.run_forever, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread is not None:
            self._thread.join(timeout=3)
            self._thread = None
        self.snapshot = BehaviorSnapshot(running=False)

    def load(self) -> None:
        """加载模型。在 worker 线程里调用，避免阻塞服务启动。"""
        import torch  # 延迟导入：没装时不影响主服务
        from ultralytics import YOLO

        torch.set_num_threads(min(4, os.cpu_count() or 1))
        base = Path(self.cfg.model_dir) if self.cfg.model_dir else Path(".")
        self.det = YOLO(str(base / "yolov8n.pt"))
        self.pose = YOLO(str(base / "yolov8n-pose.pt"))
        # 预热：首次推理会编译/初始化，先用一帧空图跑掉
        dummy = np.zeros((480, 640, 3), dtype=np.uint8)
        self.det.predict(dummy, imgsz=self.cfg.imgsz, conf=0.9, classes=[67],
                         device="cpu", verbose=False)
        self.pose.predict(dummy, imgsz=self.cfg.imgsz, conf=0.9,
                          device="cpu", verbose=False)

    def run_forever(self) -> None:
        try:
            self.load()
        except Exception as exc:  # 模型没装好也要让服务继续跑
            self.snapshot = BehaviorSnapshot(running=False, error=f"模型加载失败：{exc}")
            return
        self.snapshot = BehaviorSnapshot(running=True)
        while self._running:
            try:
                frame = self.q.get(timeout=0.5)
            except queue.Empty:
                continue
            try:
                self._infer_once(frame)
            except Exception as exc:
                self.snapshot = BehaviorSnapshot(running=True, error=f"推理异常：{exc}")

    # ==================== 对外 ====================
    @property
    def tracks(self) -> tuple[Track, ...]:
        """当前跟踪目标（标定/调试用）。"""
        return tuple(self._tracks)

    def _log(self, message: str) -> None:
        """调试打印。

        终端/管道被关闭时（例如 `python ... | head -N`）print 会抛 BrokenPipeError，
        实测它会打断推理、让检测线程整个停摆（快照冻结在旧值，
        /status 一直显示 0 人），所以这里必须吞掉异常，打不了就彻底关掉调试。
        """
        if not self.cfg.debug:
            return
        try:
            print(message, flush=True)
        except Exception:
            self.cfg.debug = False

    def process_frame(self, frame: np.ndarray) -> BehaviorSnapshot:
        """同步处理一帧（CLI 标定用）。"""
        self._infer_once(frame)
        return self.snapshot

    def clear_alerts(self) -> int:
        count = len(self._alerts)
        self._alerts = []
        self._publish(0.0)
        return count

    def emit_test(self, kind: str = "phone") -> AlertEvent:
        """造一条假告警，用于不发真实行为也能验证通知链路。"""
        self._seq += 1
        detail = kind if kind in ("phone", "sleep") else "attention"
        ev = AlertEvent(
            id=f"a{self._seq:04d}",
            kind="attention",
            track_id=0,
            ts=time.time(),
            seconds=3.0,
            box=(0, 0, 0, 0),
            score=1.0,
            evidence="这是一条测试告警（用于验证通知链路）",
            detail=detail,
        )
        self._alerts.append(ev)
        self._trim()
        self._publish(0.0)
        return ev

    # ==================== 推理主流程 ====================
    def _infer_once(self, frame: np.ndarray) -> None:
        started = time.monotonic()
        now = time.time()
        default_dt = 1.0 / max(self.cfg.infer_fps, 0.1)
        dt = (now - self._last_ts) if self._last_ts else default_dt
        # 卡顿/长间隔不放大累计，避免一次长卡顿直接触发告警
        dt = max(0.0, min(dt, 2.0))
        self._last_ts = now
        self._last_frame = frame
        self._frame_index += 1

        if self.cfg.pose_stride > 1 and self._frame_index % self.cfg.pose_stride != 0:
            # 跳帧：沿用上一帧每人的状态继续累计，省一次推理
            self._advance(dt, now)
        else:
            persons, kps_list, phones = self._run_models(frame)
            dets = [(p[0], p[1], p[2], p[3], p[4]) for p in persons]
            self._update_tracks(dets, kps_list, now)
            for tr in self._tracks:
                phone, p_score, p_ev = self._phone_evidence(tr, phones)
                sleep, s_score, s_ev = self._sleep_evidence(tr)
                tr.phone_flag, tr.phone_score, tr.phone_evidence = phone, p_score, p_ev
                tr.sleep_flag, tr.sleep_score, tr.sleep_evidence = sleep, s_score, s_ev
                self._log(f"[behavior] t{tr.tid} "
                          f"phone={int(phone)}/{p_score:.2f} sleep={int(sleep)}/{s_score:.2f} "
                          f"| {s_ev}")
            self._advance(dt, now)

        infer_ms = (time.monotonic() - started) * 1000
        self._publish(infer_ms)

    def _run_models(self, frame: np.ndarray):
        """返回 (persons, kps_list, phones)。

        persons: [(x, y, w, h, conf), ...]
        kps_list: 与 persons 对齐的 (17,3) 数组或 None
        phones: [(x1, y1, x2, y2, conf), ...]
        """
        persons: list[tuple[float, float, float, float, float]] = []
        kps_list: list[np.ndarray | None] = []
        res_p = self.pose.predict(frame, imgsz=self.cfg.imgsz,
                                  conf=self.cfg.person_conf, device="cpu", verbose=False)[0]
        raw_kps = None
        if getattr(res_p, "keypoints", None) is not None and res_p.keypoints is not None:
            raw_kps = res_p.keypoints.data.cpu().numpy()
        if res_p.boxes is not None:
            xyxy = res_p.boxes.xyxy.cpu().numpy()
            confs = res_p.boxes.conf.cpu().numpy()
            for i in range(len(xyxy)):
                x1, y1, x2, y2 = (float(v) for v in xyxy[i][:4])
                h, w = y2 - y1, x2 - x1
                if h < self.cfg.min_person_h:
                    continue
                # 只拦极端异常的框（比如整面墙/桌面被误检成人）。
                # 真人近距离坐姿宽高比可以 1.5~2.0，卡太严会把人一起丢掉；
                # 静物靠 _sleep_evidence 里的关键点可见数过滤更可靠。
                if w > self.cfg.person_max_wh_ratio * h:
                    self._log(f"[behavior] 丢弃过宽框 w={w:.0f} h={h:.0f} "
                              f"ratio={w / max(h, 1):.2f}")
                    continue
                persons.append((x1, y1, w, h, float(confs[i])))
                kps_list.append(raw_kps[i] if raw_kps is not None and i < len(raw_kps) else None)

        phones: list[tuple[float, float, float, float, float]] = []
        res_d = self.det.predict(frame, imgsz=self.cfg.imgsz, conf=self.cfg.phone_conf,
                                 classes=[67], device="cpu", verbose=False)[0]
        if res_d.boxes is not None:
            pxyxy = res_d.boxes.xyxy.cpu().numpy()
            pconf = res_d.boxes.conf.cpu().numpy()
            for i in range(len(pxyxy)):
                x1, y1, x2, y2 = (float(v) for v in pxyxy[i][:4])
                phones.append((x1, y1, x2, y2, float(pconf[i])))
        return persons, kps_list, phones

    # ==================== 跟踪 ====================
    def _update_tracks(self, dets, kps_list, now: float) -> None:
        pairs, free_t, free_d = self._match(dets)
        for ti, di in pairs:
            tr = self._tracks[ti]
            x, y, w, h, conf = dets[di]
            tr.box = (x, y, w, h)
            tr.conf = conf
            tr.kps = kps_list[di]
            tr.hits += 1
            tr.missed = 0
            tr.last_seen = now
            if tr.hits >= 2:
                tr.confirmed = True
        # 保留列表：已匹配的 + 未超期的未匹配者。**新建的必须单独保留**，
        # 否则刚 append 就被下面的过滤清掉（表现为 track id 一路递增、persons 恒为 0）。
        keep: list[Track] = [self._tracks[ti] for ti, _di in pairs]
        for ti in free_t:
            tr = self._tracks[ti]
            tr.missed += 1
            if tr.missed > self.cfg.max_missed or (now - tr.last_seen) > self.cfg.max_age:
                continue            # 连续丢失太久，丢弃
            keep.append(tr)
        created: list[Track] = []
        for di in free_d:
            if len(keep) + len(created) >= self.cfg.max_tracks:
                break
            x, y, w, h, conf = dets[di]
            self._tid += 1
            created.append(Track(tid=self._tid, box=(x, y, w, h),
                                 kps=kps_list[di], conf=conf,
                                 hits=1, last_seen=now))
        self._tracks = keep + created

    def _match(self, dets):
        """IOU 匹配，IOU 过低时退化为质心距离门控。

        采样间隔 0.33s，走动的人位移可能让 IOU 掉到 0.1，只靠 IOU 会频繁丢轨。
        """
        pairs: list[tuple[int, int]] = []
        used_t: set[int] = set()
        used_d: set[int] = set()
        # 单目标场景直接配对：误检框/抖动会让 IOU 掉到很低，若每帧都新建 track，
        # hits 永远到不了 2（confirmed 永远 False）→ 一条告警都不会产生。
        if len(self._tracks) == 1 and len(dets) == 1:
            return [(0, 0)], [], []
        cands: list[tuple[float, int, int]] = []
        for ti, tr in enumerate(self._tracks):
            tx, ty, tw, th = tr.box
            tcx, tcy = tx + tw / 2, ty + th / 2
            for di, (dx, dy, dw, dh, _conf) in enumerate(dets):
                iou = self._iou(tr.box, (dx, dy, dw, dh))
                if iou >= self.cfg.iou_gate:
                    cands.append((1.0 - iou, ti, di))
                    continue
                dcx, dcy = dx + dw / 2, dy + dh / 2
                dist = math.hypot(dcx - tcx, dcy - tcy)
                if dist <= 0.9 * max(tw, th, dw, dh) + 30:
                    cands.append((0.85, ti, di))
        cands.sort(key=lambda item: item[0])
        for cost, ti, di in cands:
            if ti in used_t or di in used_d:
                continue
            used_t.add(ti)
            used_d.add(di)
            pairs.append((ti, di))
        free_t = [i for i in range(len(self._tracks)) if i not in used_t]
        free_d = [i for i in range(len(dets)) if i not in used_d]
        return pairs, free_t, free_d

    @staticmethod
    def _iou(a, b) -> float:
        ax, ay, aw, ah = a
        bx, by, bw, bh = b
        x1, y1 = max(ax, bx), max(ay, by)
        x2, y2 = min(ax + aw, bx + bw), min(ay + ah, by + bh)
        iw, ih = max(0.0, x2 - x1), max(0.0, y2 - y1)
        inter = iw * ih
        union = aw * ah + bw * bh - inter
        return inter / union if union > 0 else 0.0

    # ==================== 行为判据 ====================
    def _phone_evidence(self, tr: Track, phones) -> tuple[bool, float, str]:
        x, y, w, h = tr.box
        hw = max(h, 1.0)
        best_d: float | None = None
        best_conf = 0.0
        for (px1, py1, px2, py2, pconf) in phones:
            cx, cy = (px1 + px2) / 2, (py1 + py2) / 2
            if not (x - 0.15 * w <= cx <= x + 1.15 * w):
                continue
            if not (y - 0.10 * h <= cy <= y + 0.85 * h):
                continue
            d = self._dist_to_upper(tr, cx, cy) / hw
            if d <= self.cfg.phone_near_ratio and (best_d is None or d < best_d):
                best_d, best_conf = d, pconf
        if best_d is not None:
            ratio = max(self.cfg.phone_near_ratio, 1e-6)
            score = min(1.0, 0.50 + 0.30 * best_conf + 0.20 * (1 - best_d / ratio))
            return True, score, f"手机框在人物上半身，距手腕/头部 {best_d:.2f}×身高"
        # 兜底：手腕贴近头部（远处检不到手机框时）
        if self.cfg.phone_wrist_fallback and h >= self.cfg.fallback_min_h:
            head = self._head_point(tr)
            if head is not None and tr.kps is not None:
                hy = head[1]
                shoulder_y = self._shoulder_y(tr)
                for wid in (L_WRIST, R_WRIST):
                    if tr.kps[wid][2] < self.cfg.kp_conf:
                        continue
                    wx, wy = float(tr.kps[wid][0]), float(tr.kps[wid][1])
                    d = math.hypot(wx - head[0], wy - hy) / hw
                    if d <= self.cfg.wrist_face_ratio and (shoulder_y is None
                                                           or wy <= shoulder_y + 0.15 * h):
                        return True, 0.50, "手腕长时间贴近头部（未检到手机框）"
        return False, 0.0, ""

    def _sleep_evidence(self, tr: Track) -> tuple[bool, float, str]:
        h = tr.box[3]
        if tr.kps is None or h < self.cfg.fallback_min_h:
            return False, 0.0, ""
        # 关键点太少说明检到的多半是静物（家具/桌面），姿态判据对它无意义
        visible = sum(
            1
            for idx in (NOSE, L_EYE, R_EYE, L_EAR, R_EAR, L_SHOULDER, R_SHOULDER)
            if self._visible(tr.kps, idx, self.cfg.kp_conf)
        )
        if visible < self.cfg.kp_min_visible:
            return False, 0.0, f"关键点不足（可见 {visible}）"
        head = self._head_point(tr)
        if head is None:
            return False, 0.0, ""
        hx, hy = head
        head_rel = (hy - tr.box[1]) / max(h, 1.0)
        shoulder_y = self._shoulder_y(tr)
        drop = None
        if shoulder_y is not None and tr.kps[NOSE][2] >= self.cfg.kp_conf:
            drop = (float(tr.kps[NOSE][1]) - shoulder_y) / max(h, 1.0)
        aspect = tr.box[2] / max(h, 1.0)
        votes = int(head_rel >= self.cfg.head_rel)
        votes += int(drop is not None and drop >= self.cfg.drop)
        votes += int(
            self.cfg.aspect_sleep <= aspect <= self.cfg.aspect_max
        )
        self._push_head(tr, hx, hy, time.time())
        move = self._head_move(tr)
        parts = [f"head_rel={head_rel:.2f}"]
        if drop is not None:
            parts.append(f"drop={drop:.2f}")
        parts.append(f"aspect={aspect:.2f}")
        parts.append(f"move={move:.3f}")
        detail = "、".join(parts)
        if self.cfg.sleep_require_still and move > self.cfg.head_move:
            return False, 0.0, f"头部仍在活动（{detail}）"
        if votes < self.cfg.sleep_votes:
            return False, 0.0, f"姿态未达标（{detail}）"
        score = min(1.0, 0.45 + 0.18 * votes + 0.15 * (1 - min(move / max(self.cfg.head_move, 1e-6), 1.0)))
        return True, score, f"头部偏低且近乎静止（{detail}）"

    # ==================== 累计与触发 ====================
    def _advance(self, dt: float, now: float) -> None:
        frame = self._last_frame
        for tr in list(self._tracks):
            for flag, sec_attr, gap_attr in ((tr.phone_flag, "phone_sec", "phone_gap"),
                                             (tr.sleep_flag, "sleep_sec", "sleep_gap")):
                if flag:
                    setattr(tr, sec_attr, getattr(tr, sec_attr) + dt)
                    setattr(tr, gap_attr, 0.0)
                else:
                    gap = getattr(tr, gap_attr) + dt
                    setattr(tr, gap_attr, gap)
                    if gap > self.cfg.reset_gap:
                        setattr(tr, sec_attr, 0.0)
            # 合并成一种告警「注意力不集中」，具体表现放在 detail / evidence 里
            if tr.phone_sec >= self.cfg.phone_hold:
                self._try_emit(tr, "attention", now, frame, detail="phone")
            if tr.sleep_sec >= self.cfg.sleep_hold:
                self._try_emit(tr, "attention", now, frame, detail="sleep")

    def _try_emit(self, tr: Track, kind: str, now: float, frame: np.ndarray | None,
                  detail: str = "attention") -> AlertEvent | None:
        if not tr.confirmed:
            return None
        # 冷却键统一用 attention：合并后同一人 60 秒内只报一次
        if now - tr.last_alert.get("attention", -1e9) < self.cfg.cooldown:
            return None
        if not self._rate_ok(now):
            return None
        self._seq += 1
        if detail == "phone":
            seconds, score, evidence = tr.phone_sec, tr.phone_score, tr.phone_evidence
        else:
            seconds, score, evidence = tr.sleep_sec, tr.sleep_score, tr.sleep_evidence
        ev = AlertEvent(
            id=f"a{self._seq:04d}",
            kind="attention",
            track_id=tr.tid,
            ts=now,
            seconds=seconds,
            box=tuple(int(v) for v in tr.box),
            score=score,
            evidence=evidence or "注意力不集中",
            detail=detail,
        )
        if self.cfg.save_snapshot and frame is not None:
            ev.snapshot = self._save_snapshot(frame, tr, detail, now)
        tr.last_alert["attention"] = now
        # 触发后清零，需重新累计（60s 冷却是主约束，这里避免连续刷同一条）
        tr.phone_sec = 0.0
        tr.sleep_sec = 0.0
        self._alerts.append(ev)
        self._trim()
        # 立刻发布，别让告警等到下一帧才出现在 /alerts 里
        self._publish(0.0)
        self._log(f"[behavior] ALERT {ev.id} {kind} track={tr.tid} "
                  f"{ev.seconds:.1f}s score={ev.score:.2f}")
        return ev

    def _rate_ok(self, now: float) -> bool:
        while self._minute and now - self._minute[0] > 60.0:
            self._minute.popleft()
        if len(self._minute) >= self.cfg.global_limit:
            return False
        self._minute.append(now)
        return True

    def _trim(self) -> None:
        if len(self._alerts) > self.cfg.history:
            del self._alerts[: len(self._alerts) - self.cfg.history]

    def _save_snapshot(self, frame: np.ndarray, tr: Track, kind: str, now: float) -> str:
        """存留证截图。中文路径必须走 imwrite_safe，文件名纯 ASCII。"""
        try:
            from .capture import imwrite_safe
        except Exception:
            return ""
        name = (f"alert_{time.strftime('%Y%m%d_%H%M%S', time.localtime(now))}"
                f"_t{tr.tid}_{kind}.jpg")
        drawn = frame.copy()
        x, y, w, h = (int(v) for v in tr.box)
        color = (0, 140, 255) if kind == "phone" else (60, 60, 235)
        cv2_draw(drawn, x, y, w, h, kind.upper(), color)
        try:
            ok = imwrite_safe(self.output_dir / name, drawn)
        except Exception:
            return ""
        return name if ok else ""

    # ==================== 关键点小工具 ====================
    @staticmethod
    def _visible(kps: np.ndarray, idx: int, conf: float) -> bool:
        return kps[idx][2] >= conf

    def _head_point(self, tr: Track) -> tuple[float, float] | None:
        if tr.kps is None:
            return None
        xs: list[float] = []
        ys: list[float] = []
        for idx in _HEAD_IDS:
            if self._visible(tr.kps, idx, self.cfg.kp_conf):
                xs.append(float(tr.kps[idx][0]))
                ys.append(float(tr.kps[idx][1]))
        if not xs:
            return None
        return sum(xs) / len(xs), sum(ys) / len(ys)

    def _shoulder_y(self, tr: Track) -> float | None:
        if tr.kps is None:
            return None
        ys: list[float] = []
        for idx in (L_SHOULDER, R_SHOULDER):
            if self._visible(tr.kps, idx, self.cfg.kp_conf):
                ys.append(float(tr.kps[idx][1]))
        return sum(ys) / len(ys) if ys else None

    def _dist_to_upper(self, tr: Track, cx: float, cy: float) -> float:
        """到「上半身参照点」（手腕/鼻尖，缺失时用头部质心）的最小距离。"""
        cands: list[tuple[float, float]] = []
        if tr.kps is not None:
            for idx in (L_WRIST, R_WRIST, NOSE):
                if self._visible(tr.kps, idx, self.cfg.kp_conf):
                    cands.append((float(tr.kps[idx][0]), float(tr.kps[idx][1])))
        if not cands:
            head = self._head_point(tr)
            if head is None:
                return math.hypot(cx - (tr.box[0] + tr.box[2] / 2), cy - tr.box[1])
            cands = [head]
        return min(math.hypot(cx - px, cy - py) for px, py in cands)

    def _push_head(self, tr: Track, hx: float, hy: float, now: float) -> None:
        tr.head_hist.append((now, hx, hy))

    def _head_move(self, tr: Track) -> float:
        """头部位移速度（× 框高 / 秒）。用于区分「瞌睡」与「低头写字」。"""
        hist = tr.head_hist
        if len(hist) < 3:
            return 0.0
        total = 0.0
        for i in range(1, len(hist)):
            _t0, x0, y0 = hist[i - 1]
            _t1, x1, y1 = hist[i]
            total += math.hypot(x1 - x0, y1 - y0)
        span = max(hist[-1][0] - hist[0][0], 1e-3)
        return (total / span) / max(tr.box[3], 1.0)

    # ==================== 快照发布 ====================
    def _publish(self, infer_ms: float) -> None:
        boxes: list[tuple[int, int, int, int, str, float]] = []
        phone_now = 0
        sleep_now = 0
        for tr in self._tracks:
            if not tr.confirmed:
                continue
            if tr.phone_flag:
                phone_now += 1
                boxes.append((int(tr.box[0]), int(tr.box[1]), int(tr.box[2]),
                              int(tr.box[3]), "phone", tr.phone_score))
            if tr.sleep_flag:
                sleep_now += 1
                boxes.append((int(tr.box[0]), int(tr.box[1]), int(tr.box[2]),
                              int(tr.box[3]), "sleep", tr.sleep_score))
        self.snapshot = BehaviorSnapshot(
            running=True,
            error="",
            infer_ms=infer_ms,
            persons=len(self._tracks),
            phone_now=phone_now,
            sleep_now=sleep_now,
            boxes=tuple(boxes),
            alerts=tuple(self._alerts),
        )


def cv2_draw(image: np.ndarray, x: int, y: int, w: int, h: int,
             label: str, color: tuple[int, int, int]) -> None:
    """在截图上画告警框。cv2.putText 不支持中文，标签必须是英文。"""
    import cv2

    cv2.rectangle(image, (x, y), (x + w, y + h), color, 2)
    cv2.putText(image, label, (x, max(20, y - 6)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
