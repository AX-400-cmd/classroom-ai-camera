import argparse
import hmac
import json
import queue
import threading
import time
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import cv2

from .behavior import BehaviorConfig, BehaviorDetector
from .capture import CameraCapture, imwrite_safe, pick_encoder
from .media import (
    delete_media,
    list_media,
    poster_jpeg,
    read_json_body,
    safe_media_path,
    write_file_response,
)
from .ptz import PTZConfig, create_ptz_controller
from .stats import StatsStore
from .wechat import WeChatNotifier


INDEX_HTML = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>智能课堂 AI 摄像头 MVP</title>
  <style>
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:#101418; color:#eef3f8; }
    header { padding: 18px 24px; background:#171d24; border-bottom:1px solid #2b3440; }
    h1 { margin:0; font-size:20px; }
    main { padding: 20px; max-width: 1100px; margin: 0 auto; }
    .video-wrap { background:#000; border-radius:14px; overflow:hidden; border:1px solid #2b3440; }
    img { display:block; width:100%; min-height:420px; object-fit:contain; background:#000; cursor:crosshair; }
    .controls { display:flex; gap:12px; align-items:center; flex-wrap:wrap; margin-top:16px; }
    button { border:0; border-radius:10px; padding:11px 18px; cursor:pointer; font-weight:700; }
    .start { background:#25c26e; color:#06110b; }
    .stop { background:#ff5c5c; color:white; }
    .shot { background:#3b82f6; color:white; }
    .status { padding:10px 12px; background:#171d24; border:1px solid #2b3440; border-radius:10px; }
    .hint { color:#9aa7b3; margin-top:14px; line-height:1.6; }
    a { color:#7db7ff; }
  </style>
</head>
<body>
  <header><h1>智能课堂 AI 摄像头 MVP</h1></header>
  <main>
    <div class="video-wrap"><img id="preview" src="/video_feed" alt="摄像头预览"></div>
    <div class="controls">
      <button class="start" onclick="api('/start')">开始录制</button>
      <button class="stop" onclick="api('/stop')">停止录制</button>
      <button class="shot" onclick="api('/snapshot')">保存截图</button>
      <button class="shot" onclick="api('/clear_target')">清除目标</button>
      <span class="status" id="status">正在连接…</span>
    </div>
    <p class="hint">
      当前为 MVP：支持浏览器预览、截图、本地 MP4 录制。点击画面中的教师位置，可生成目标框并进行基础跟踪。
    </p>
  </main>
  <script>
    async function api(path) {
      const res = await fetch(path, {method:'POST'});
      const data = await res.json();
      document.getElementById('status').textContent = data.message || JSON.stringify(data);
    }
    document.getElementById('preview').addEventListener('click', async (e) => {
      const img = e.currentTarget;
      const rect = img.getBoundingClientRect();
      const x = (e.clientX - rect.left) / rect.width;
      const y = (e.clientY - rect.top) / rect.height;
      const res = await fetch('/select_target', {
        method: 'POST',
        headers: {'Content-Type':'application/json'},
        body: JSON.stringify({x, y})
      });
      const data = await res.json();
      document.getElementById('status').textContent = data.message || JSON.stringify(data);
    });
    async function refreshStatus() {
      try {
        const res = await fetch('/status');
        const data = await res.json();
        document.getElementById('status').textContent =
          data.recording ? `录制中：${data.recording_path}` : '未录制';
      } catch(e) {
        document.getElementById('status').textContent = '连接失败';
      }
    }
    setInterval(refreshStatus, 1500);
    refreshStatus();
  </script>
</body>
</html>
"""


REPORT_HTML = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>课堂统计报表</title>
  <style>
    body { margin:0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
           background:#101418; color:#eef3f8; }
    header { padding:18px 24px; background:#171d24; border-bottom:1px solid #2b3440;
             display:flex; align-items:center; gap:16px; flex-wrap:wrap; }
    h1 { margin:0; font-size:20px; }
    .seg { display:flex; gap:6px; }
    .seg button { border:1px solid #2b3440; background:#171d24; color:#cdd6df;
                  border-radius:8px; padding:6px 14px; cursor:pointer; font-weight:600; }
    .seg button.on { background:#3b82f6; color:#fff; border-color:#3b82f6; }
    main { padding:20px; max-width:1100px; margin:0 auto; }
    .cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; }
    .card { background:#171d24; border:1px solid #2b3440; border-radius:12px; padding:14px 16px; }
    .card .v { font-size:26px; font-weight:800; }
    .card .l { color:#9aa7b3; font-size:13px; margin-top:4px; }
    .card .s { color:#6f7c89; font-size:12px; margin-top:2px; }
    .panel { background:#171d24; border:1px solid #2b3440; border-radius:12px; padding:16px; margin-top:16px; }
    .panel h2 { margin:0 0 12px; font-size:15px; color:#cdd6df; }
    .bars { display:flex; align-items:flex-end; gap:4px; height:200px; }
    .bars .col { flex:1; display:flex; flex-direction:column; justify-content:flex-end; align-items:center; }
    .bars .bar { width:100%; background:linear-gradient(#3b82f6,#2563eb); border-radius:4px 4px 0 0; min-height:2px; }
    .bars .lab { font-size:10px; color:#6f7c89; margin-top:4px; }
    .bars .cnt { font-size:10px; color:#9aa7b3; }
    .hint { color:#9aa7b3; margin-top:14px; line-height:1.6; font-size:13px; }
    a { color:#7db7ff; }
  </style>
</head>
<body>
  <header>
    <h1>课堂统计报表</h1>
    <div class="seg" id="seg">
      <button data-r="day" class="on">今日</button>
      <button data-r="week">近 7 天</button>
      <button data-r="all">全部</button>
    </div>
  </header>
  <main>
    <div class="cards" id="cards"></div>
    <div class="panel">
      <h2>24 小时告警分布</h2>
      <div class="bars" id="bars"></div>
    </div>
    <p class="hint">数据来自服务端 SQLite（outputs/stats.db）：告警事件与人数采样实时落盘，重启服务不丢。
       到课人数取统计区间内「画面人数峰值」，注意力人数取平均。手机 APP 端报表页后续版本接入。</p>
  </main>
  <script>
    const fmt = n => (n==null?'-':n);
    async function load(range){
      const res = await fetch('/stats?range='+range);
      const data = await res.json();
      const s = data.summary || {};
      const detail = s.by_detail || {};
      const cards = [
        ['告警总数', fmt(s.alert_total), '起'],
        ['累计时长', fmt(s.alert_total_seconds), '秒'],
        ['玩手机', fmt(detail.phone||0), '起'],
        ['打瞌睡', fmt(detail.sleep||0), '起'],
        ['到课人数(峰值)', fmt(s.persons_max), '人'],
        ['平均注意力人数', fmt(s.attention_avg), '人'],
        ['最易分心时段', s.top_hour>=0? s.top_hour+':00' : '-', ''],
      ];
      document.getElementById('cards').innerHTML = cards.map(c=>
        '<div class="card"><div class="v">'+c[1]+'</div>'+
        '<div class="l">'+c[0]+'</div><div class="s">'+c[2]+'</div></div>').join('');
      const hours = s.by_hour || new Array(24).fill(0);
      const max = Math.max(1, ...hours);
      document.getElementById('bars').innerHTML = hours.map((v,i)=>
        '<div class="col"><div class="cnt">'+v+'</div>'+
        '<div class="bar" style="height:'+(v/max*160)+'px"></div>'+
        '<div class="lab">'+i+'</div></div>').join('');
    }
    document.getElementById('seg').addEventListener('click', e=>{
      const b = e.target.closest('button'); if(!b) return;
      document.querySelectorAll('#seg button').forEach(x=>x.classList.remove('on'));
      b.classList.add('on');
      load(b.dataset.r);
    });
    load('day');
  </script>
</body>
</html>
"""


class CameraService:
    def __init__(self, source: str, output_dir: str, ptz_config: PTZConfig | None = None,
                 fourcc: str = "auto", behavior: BehaviorConfig | None = None,
                 camera_size: tuple[int, int] = (0, 0),
                 wx_config: str = ""):
        self.wx = WeChatNotifier(wx_config, enabled=bool(wx_config))
        self.camera = CameraCapture(source, output_dir,
                                    width=camera_size[0], height=camera_size[1])
        self.output_dir = Path(output_dir)
        self.lock = threading.RLock()
        self.frame = None
        self.jpeg = None
        self.jpeg_raw = None          # 未叠加目标框的原始帧，供 APP 自己画框
        self.frame_size = None        # (width, height)，APP 画框换算必需
        self.running = False
        self.recording_path = None
        self.tracker = None
        self.target_box = None
        self.target_status = "未选择目标"
        self.target_status_code = "none"   # none | tracking | lost
        self.ptz = create_ptz_controller(ptz_config)
        self.ptz_status = "未启用"
        if ptz_config and ptz_config.enabled:
            self.ptz_status = f"已连接 {ptz_config.backend}:{ptz_config.host}:{ptz_config.port}"
        self.thread = None
        # 录制编码：auto 时探测浏览器可播的编码器
        self.record_codec, self.record_ext = pick_encoder(str(self.output_dir), fourcc)
        # 行为检测：推理在独立 worker 线程，结果走不可变快照回传，
        # 绝不在这里持 self.lock 做推理（会卡死 /status 与 /frame.jpg）。
        self.behavior_cfg = behavior or BehaviorConfig()
        self._behavior_queue: "queue.Queue" = queue.Queue(maxsize=1)
        self.behavior = BehaviorDetector(str(self.output_dir),
                                         self.behavior_cfg, self._behavior_queue)
        self._last_submit = 0.0
        # 课堂统计：告警 + 人数采样落盘（SQLite），供 /stats、/report 聚合
        self.stats = StatsStore(self.output_dir / "stats.db")
        self._last_stats = 0.0
        self._stats_last_alert_id = ""
        # 微信订阅消息推送：未配置时 push_alert 内部直接返回 0，不影响任何主流程
        self._push_last_alert_id = ""

    def _wechat_push(self, alert) -> None:
        """推送告警给小程序订阅者。已在采集线程调用，异常一律内部吞掉。"""
        try:
            self.wx.push_alert(alert)
        except Exception as exc:
            print(f"[wechat] 推送异常（已忽略）：{exc}")

    def start(self):
        self.camera.open()
        self.running = True
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()
        if self.behavior_cfg.enabled:
            # 模型加载失败也不能拖垮主服务：失败信息会体现在 behavior_error 里
            try:
                self.behavior.start()
            except Exception as exc:
                self.behavior.snapshot = self.behavior.snapshot.__class__(
                    running=False, error=f"行为检测启动失败：{exc}")

    def _maybe_submit(self, frame) -> None:
        """采集线程调用（持锁段内）：只做一次内存拷贝，绝不推理。

        采样间隔到点才提交；队列满则丢旧帧，worker 永远处理最新一帧。
        """
        cfg = self.behavior_cfg
        if not cfg.enabled or not self.behavior.snapshot.running:
            return
        now = time.monotonic()
        if now - self._last_submit < 1.0 / max(cfg.infer_fps, 0.1):
            return
        self._last_submit = now
        q = self._behavior_queue
        if q.full():
            try:
                q.get_nowait()
            except queue.Empty:
                pass
        try:
            q.put_nowait(frame.copy())
        except queue.Full:
            pass

    def _loop(self):
        while self.running:
            ok, frame = self.camera.read()
            if ok:
                with self.lock:
                    fh, fw = frame.shape[:2]
                    self.frame_size = (int(fw), int(fh))
                    # 原始帧：APP 用 ?raw=1 拿这一份，自己叠加目标框
                    ok_raw, raw = cv2.imencode(
                        ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 82]
                    )
                    if ok_raw:
                        self.jpeg_raw = raw.tobytes()
                    display = frame.copy()
                    if self.tracker is not None:
                        tracked, box = self.tracker.update(frame)
                        if tracked:
                            self.target_box = tuple(int(v) for v in box)
                            self.target_status = "跟踪中"
                            self.target_status_code = "tracking"
                            x, y, w, h = self.target_box
                            fh, fw = frame.shape[:2]
                            error_x = ((x + w / 2) - fw / 2) / (fw / 2)
                            error_y = ((y + h / 2) - fh / 2) / (fh / 2)
                            try:
                                self.ptz.move_by_error(error_x, error_y)
                            except Exception as exc:
                                self.ptz_status = f"PTZ 控制失败：{exc}"
                        else:
                            self.target_status = "目标丢失"
                            self.target_status_code = "lost"
                            self.ptz.stop()
                    if self.target_box is not None:
                        x, y, w, h = self.target_box
                        color = (37, 194, 110) if self.target_status == "跟踪中" else (0, 92, 255)
                        cv2.rectangle(display, (x, y), (x + w, y + h), color, 2)
                        cv2.putText(display, f"Teacher: {self.target_status}", (x, max(24, y - 8)),
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
                    # 行为告警框：读不可变快照（零阻塞），标签必须英文
                    # —— cv2.putText 画中文会输出 ??
                    snap = self.behavior.snapshot
                    for (bx, by, bw, bh, kind, score) in snap.boxes:
                        color = (0, 140, 255) if kind == "phone" else (60, 60, 235)
                        cv2.rectangle(display, (bx, by), (bx + bw, by + bh), color, 2)
                        cv2.putText(display, f"{kind.upper()} {score:.2f}",
                                    (bx, max(20, by - 6)),
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)
                    ok_jpg, jpg = cv2.imencode(".jpg", display, [int(cv2.IMWRITE_JPEG_QUALITY), 82])
                    self.frame = frame
                    if ok_jpg:
                        self.jpeg = jpg.tobytes()
                    # 抽帧给行为检测 worker（只拷贝，不推理）
                    self._maybe_submit(frame)
                    # 统计落盘（5s 节流）：人数采样 + 增量写告警
                    now_m = time.monotonic()
                    if now_m - self._last_stats >= 5.0:
                        self._last_stats = now_m
                        snap = self.behavior.snapshot
                        if snap.running:
                            self.stats.record_sample(
                                snap.persons, snap.phone_now + snap.sleep_now)
                            for a in snap.alerts:
                                if a.id > self._stats_last_alert_id:
                                    self.stats.record_alert(a)
                                    self._stats_last_alert_id = a.id
                    # 新告警立刻推微信订阅消息（每帧只比较 id，开销可忽略，
                    # 不跟着 5s 统计节流走，避免告警延迟一个采样周期才送达）
                    snap_now = self.behavior.snapshot
                    if snap_now.alerts:
                        last = snap_now.alerts[-1]
                        if last.id > self._push_last_alert_id:
                            self._push_last_alert_id = last.id
                            self._wechat_push(last)
            time.sleep(0.03)

    def stop(self):
        self.running = False
        if self.thread:
            self.thread.join(timeout=2)
        self.behavior.stop()
        self.camera.close()
        self.ptz.close()
        self.stats.close()

    def start_recording(self):
        with self.lock:
            if self.frame is None:
                raise RuntimeError("还没有读取到摄像头画面")
            if self.camera.writer is not None:
                return self.recording_path
            height, width = self.frame.shape[:2]
            self.recording_path = self.camera.start_recording(
                (width, height), fourcc=self.record_codec, ext=self.record_ext
            )
            return self.recording_path

    def stop_recording(self):
        self.camera.stop_recording()
        old = self.recording_path
        self.recording_path = None
        return old

    def snapshot(self):
        with self.lock:
            if self.frame is None:
                raise RuntimeError("还没有读取到摄像头画面")
            self.output_dir.mkdir(parents=True, exist_ok=True)
            path = self.output_dir / f"snapshot_{time.strftime('%Y%m%d_%H%M%S')}.jpg"
            if not imwrite_safe(path, self.frame):
                raise RuntimeError(f"截图写入失败：{path}")
            return path

    def select_target(self, nx: float, ny: float):
        with self.lock:
            if self.frame is None:
                raise RuntimeError("还没有读取到摄像头画面")
            height, width = self.frame.shape[:2]
            cx = int(max(0, min(1, nx)) * width)
            cy = int(max(0, min(1, ny)) * height)
            box_w = max(80, min(180, width // 4))
            box_h = max(120, min(280, height // 2))
            x = max(0, min(width - box_w, cx - box_w // 2))
            y = max(0, min(height - box_h, cy - box_h // 2))
            self.tracker = cv2.TrackerMIL_create()
            self.target_box = (x, y, box_w, box_h)
            self.tracker.init(self.frame, self.target_box)
            self.target_status = "跟踪中"
            self.target_status_code = "tracking"
            return self.target_box

    def clear_target(self):
        with self.lock:
            self.tracker = None
            self.target_box = None
            self.target_status = "未选择目标"
            self.target_status_code = "none"
            self.ptz.stop()


def make_handler(service: CameraService, api_token: str = ""):
    """构造请求处理器。

    `api_token` 为空表示**关闭鉴权**，行为与旧版本完全一致（局域网自用场景）；
    一旦配置了非空令牌，除 `/healthz` 外的所有接口都必须携带正确令牌，
    否则返回 401。上线到公网/校园网必须配置此项——否则任何人拿到地址就能
    看教室实时画面、清空告警、删除录像。
    """
    _token = (api_token or "").strip()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            return

        # ---------- 鉴权 ----------

        def _authorized(self) -> bool:
            """校验访问令牌。

            支持两种传参，缺一不可：
            - `Authorization: Bearer <token>`：APP / 脚本 / curl 用；
            - `?token=<token>`：`<image src>` 与小程序 image 组件无法自定义请求头，
              抓帧、封面缩略图只能走 query。
            """
            if not _token:
                return True
            supplied = ""
            header = self.headers.get("Authorization") or ""
            if header.lower().startswith("bearer "):
                supplied = header[7:].strip()
            if not supplied:
                supplied = (parse_qs(urlparse(self.path).query)
                            .get("token") or [""])[0].strip()
            # 恒定时间比较，避免按响应时间逐字符爆破
            return hmac.compare_digest(supplied, _token)

        def _deny(self):
            self._json({"ok": False, "message": "未授权：缺少或错误的访问令牌"},
                       HTTPStatus.UNAUTHORIZED)

        def _cors(self):
            """所有响应统一加 CORS 头。

            缺了 Access-Control-Allow-Origin，浏览器（含 Flutter Web）会直接拦截响应，
            客户端只能拿到一个不可读的错误；Access-Control-Allow-Private-Network 用于
            绕过 Chrome 对 localhost -> 192.168.x.x 的私有网络访问预检。
            """
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Private-Network", "true")
            self.send_header(
                "Access-Control-Expose-Headers",
                "Content-Length, Content-Range, Accept-Ranges, Content-Disposition, "
                "X-Frame-Width, X-Frame-Height, X-Target-Box, X-Target-Status",
            )

        def _error(self, status: HTTPStatus, message: str):
            """替代 send_error —— send_error 不带 CORS，Web 端读不到错误体。"""
            self._json({"ok": False, "message": message}, status)

        def _json(self, data, status=HTTPStatus.OK):
            body = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self._cors()
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = urlparse(self.path).path
            # 健康检查免鉴权：守护脚本/负载均衡探活用，不泄露任何业务数据
            if path == "/healthz":
                self._json({"ok": True, "service": "classroom-camera"})
                return
            if not self._authorized():
                self._deny()
                return
            if path == "/":
                body = INDEX_HTML.encode("utf-8")
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self._cors()
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif path == "/status":
                with service.lock:
                    fw, fh = service.frame_size or (0, 0)
                    box = service.target_box
                    code = service.target_status_code
                    rec_path = service.recording_path
                # 行为检测状态：整体读一次快照，不与 service.lock 嵌套
                snap = service.behavior.snapshot
                last_alert = snap.alerts[-1] if snap.alerts else None
                self._json({
                    # --- 旧字段，语义保持不变 ---
                    "recording": service.camera.writer is not None,
                    "recording_path": str(rec_path) if rec_path else "",
                    "target_status": service.target_status,
                    "target_box": list(box) if box else None,
                    "ptz_status": service.ptz_status,
                    # --- 新增字段（只增不减）---
                    "frame_width": fw,          # APP 画目标框的换算基准
                    "frame_height": fh,
                    "target_status_code": code,  # none | tracking | lost
                    "recording_name": Path(rec_path).name if rec_path else "",
                    "record_codec": service.record_codec,
                    "output_dir": str(Path(service.output_dir).resolve()),
                    "server_time": time.time(),
                    # --- 行为检测（默认关闭时全是空值，老 APP 不受影响）---
                    "behavior_enabled": service.behavior_cfg.enabled,
                    "behavior_running": snap.running,
                    "behavior_error": snap.error,
                    "behavior_persons": snap.persons,
                    "behavior_phone": snap.phone_now,
                    "behavior_sleep": snap.sleep_now,
                    # [x, y, w, h, kind, score]，APP 端用原始帧自己画框
                    "behavior_boxes": [list(b) for b in snap.boxes],
                    "alert_count": len(snap.alerts),
                    "alert_last_id": last_alert.id if last_alert else "",
                    "alert_last_ts": last_alert.ts if last_alert else 0,
                    "alert_last_kind": last_alert.kind if last_alert else "",
                })
            elif path == "/video_feed":
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
                self._cors()
                self.end_headers()
                while True:
                    with service.lock:
                        jpg = service.jpeg
                    if jpg:
                        try:
                            self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" + jpg + b"\r\n")
                        except (BrokenPipeError, ConnectionResetError):
                            break
                    time.sleep(0.05)
            elif path == "/frame.jpg":
                query = parse_qs(urlparse(self.path).query)
                raw = query.get("raw", ["0"])[0] in ("1", "true", "yes")
                # ?w=640：按宽度缩放后再编码。小程序走内网穿透时用它省带宽
                try:
                    scale_w = int(query.get("w", ["0"])[0] or 0)
                except ValueError:
                    scale_w = 0
                with service.lock:
                    jpg = service.jpeg_raw if raw else service.jpeg
                    box = service.target_box
                    code = service.target_status_code
                    fw, fh = service.frame_size or (0, 0)
                if not jpg:
                    self._error(HTTPStatus.SERVICE_UNAVAILABLE, "摄像头画面尚未准备好")
                    return
                out_w, out_h = fw, fh
                if scale_w > 0 and fw and fw > scale_w:
                    try:
                        import numpy as np
                        arr = np.frombuffer(jpg, dtype=np.uint8)
                        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                        if img is not None:
                            out_h = max(1, int(img.shape[0] * scale_w / img.shape[1]))
                            out_w = scale_w
                            img = cv2.resize(img, (out_w, out_h),
                                             interpolation=cv2.INTER_AREA)
                            ok_s, buf = cv2.imencode(
                                ".jpg", img, [int(cv2.IMWRITE_JPEG_QUALITY), 78])
                            if ok_s:
                                jpg = buf.tobytes()
                    except Exception:
                        pass  # 缩放失败就用原图，不能影响预览
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
                self.send_header("Pragma", "no-cache")
                self._cors()
                # 与这一帧同一时刻的目标框，APP 可直接用它叠加，零滞后
                self.send_header("X-Frame-Width", str(out_w))
                self.send_header("X-Frame-Height", str(out_h))
                self.send_header("X-Target-Box", ",".join(str(int(v)) for v in box) if box else "-")
                self.send_header("X-Target-Status", code)
                self.send_header("Content-Length", str(len(jpg)))
                self.end_headers()
                self.wfile.write(jpg)
            elif path == "/files":
                query = parse_qs(urlparse(self.path).query)
                kind = (query.get("kind", ["all"])[0] or "all").lower()
                rec_name = Path(service.recording_path).name if service.recording_path else ""
                files = list_media(service.output_dir, kind, rec_name)
                self._json({
                    "ok": True,
                    "output_dir": str(Path(service.output_dir).resolve()),
                    "files": files,
                })
            elif path == "/files/download":
                query = parse_qs(urlparse(self.path).query)
                target = safe_media_path(service.output_dir, query.get("name", [""])[0])
                if target is None:
                    self._error(HTTPStatus.NOT_FOUND, "文件不存在")
                    return
                disposition = "attachment" if query.get("disposition", ["inline"])[0] == "attachment" else "inline"
                write_file_response(self, target, disposition=disposition, body=(self.command != "HEAD"))
            elif path == "/files/poster":
                query = parse_qs(urlparse(self.path).query)
                target = safe_media_path(service.output_dir, query.get("name", [""])[0])
                if target is None:
                    self._error(HTTPStatus.NOT_FOUND, "无法生成封面")
                    return
                data = poster_jpeg(target)
                if not data:
                    self._error(HTTPStatus.NOT_FOUND, "无法解码该视频（可能仍在写入或编码不受支持）")
                    return
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "image/jpeg")
                self._cors()
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            elif path == "/wx/status":
                # 小程序端用它判断「推送配置好了没」，不做任何网络请求
                self._json({"ok": True, **service.wx.status()})
            elif path == "/stats":
                # 课堂统计聚合：日报 / 周报 / 全部
                query = parse_qs(urlparse(self.path).query)
                range_ = (query.get("range", ["day"])[0] or "day").lower()
                if range_ not in ("day", "week", "all"):
                    range_ = "day"
                self._json({"ok": True, "summary": service.stats.summary(range_)})
            elif path == "/report":
                body = REPORT_HTML.encode("utf-8")
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self._cors()
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif path == "/alerts":
                # do_GET 整体没有 try/except，这里必须自己兜住异常，
                # 否则会走 BaseHTTPRequestHandler 默认 send_error（不带 CORS 头，
                # 客户端只能拿到一个不可读的错误）。
                try:
                    query = parse_qs(urlparse(self.path).query)
                    since = (query.get("since", [""])[0] or "").strip()
                    try:
                        limit = int(query.get("limit", ["50"])[0] or "50")
                    except ValueError:
                        limit = 50
                    snap = service.behavior.snapshot
                    items = ([a for a in snap.alerts if a.id > since]
                             if since else list(snap.alerts))
                    if limit > 0 and len(items) > limit:
                        items = items[-limit:]
                    self._json({
                        "ok": True,
                        "server_time": time.time(),
                        "enabled": service.behavior_cfg.enabled,
                        "running": snap.running,
                        "error": snap.error,
                        "last_id": snap.last_id,
                        "alerts": [a.to_dict() for a in items],
                    })
                except Exception as exc:
                    self._json({"ok": False, "message": f"获取告警失败：{exc}"},
                               HTTPStatus.INTERNAL_SERVER_ERROR)
            else:
                self._error(HTTPStatus.NOT_FOUND, f"未知接口：{path}")

        def do_HEAD(self):
            self.do_GET()

        def do_OPTIONS(self):
            self.send_response(HTTPStatus.NO_CONTENT)
            self._cors()
            self.send_header("Access-Control-Allow-Methods", "GET, HEAD, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers",
                             "Content-Type, Range, Authorization")
            self.send_header("Access-Control-Max-Age", "600")
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_POST(self):
            path = urlparse(self.path).path
            if not self._authorized():
                self._deny()
                return
            try:
                if path == "/start":
                    p = service.start_recording()
                    self._json({"ok": True, "message": f"开始录制：{p}"})
                elif path == "/stop":
                    p = service.stop_recording()
                    self._json({"ok": True, "message": f"已停止录制：{p}" if p else "当前没有录制"})
                elif path == "/snapshot":
                    p = service.snapshot()
                    self._json({"ok": True, "message": f"截图已保存：{p}"})
                elif path == "/select_target":
                    data = read_json_body(self)
                    box = service.select_target(float(data.get("x", 0.5)), float(data.get("y", 0.5)))
                    self._json({"ok": True, "message": f"已选择教师目标：{box}"})
                elif path == "/clear_target":
                    service.clear_target()
                    self._json({"ok": True, "message": "已清除教师目标"})
                elif path == "/files/delete":
                    data = read_json_body(self)
                    name = str(data.get("name", ""))
                    rec_name = Path(service.recording_path).name if service.recording_path else ""
                    if name and name == rec_name:
                        self._json({"ok": False, "message": "该文件正在录制中，请先停止录制"},
                                   HTTPStatus.CONFLICT)
                        return
                    ok, message, status = delete_media(service.output_dir, name)
                    self._json({"ok": ok, "message": message}, status)
                elif path == "/alerts/clear":
                    count = service.behavior.clear_alerts()
                    self._json({"ok": True, "message": f"已清空 {count} 条告警"})
                elif path == "/alerts/test":
                    # 不发真实行为也能验证「后端 → APP 通知」整条链路
                    data = {}
                    try:
                        data = read_json_body(self)
                    except Exception:
                        data = {}
                    ev = service.behavior.emit_test(str(data.get("kind", "phone")))
                    self._json({"ok": True, "message": f"已生成测试告警 {ev.id}",
                                "alert": ev.to_dict()})
                elif path == "/behavior/stop":
                    service.behavior.stop()
                    self._json({"ok": True, "message": "行为检测已停止"})
                elif path == "/behavior/start":
                    service.behavior.start()
                    self._json({"ok": True, "message": "行为检测已启动（模型加载约需数秒）"})
                # --- 微信小程序：登录 / 订阅 / 推送 ---
                elif path == "/wx/login":
                    data = read_json_body(self)
                    res = service.wx.code2session(str(data.get("code", "")))
                    if not res.get("ok"):
                        self._json({"ok": False, "message": res.get("message", "登录失败")},
                                   HTTPStatus.BAD_GATEWAY)
                        return
                    openid = res["openid"]
                    service.wx.add_subscriber(openid, quota=0,
                                              note=str(data.get("note", ""))[:80])
                    self._json({"ok": True, "openid": openid,
                                "quota": service.wx.status().get("quota_total", 0),
                                "configured": service.wx.configured})
                elif path == "/wx/subscribe":
                    # 小程序端 wx.requestSubscribeMessage 授权成功后上报，攒下发额度
                    data = read_json_body(self)
                    openid = str(data.get("openid", ""))
                    try:
                        count = int(data.get("count", 1))
                    except (TypeError, ValueError):
                        count = 1
                    if not openid:
                        self._json({"ok": False, "message": "缺少 openid"},
                                   HTTPStatus.BAD_REQUEST)
                        return
                    info = service.wx.add_subscriber(openid, quota=max(1, count))
                    self._json({"ok": True, "message": "订阅成功", **info})
                elif path == "/wx/unbind":
                    data = read_json_body(self)
                    ok = service.wx.remove_subscriber(str(data.get("openid", "")))
                    self._json({"ok": ok,
                                "message": "已取消订阅" if ok else "该用户未订阅"})
                elif path == "/wx/test":
                    # 发一条测试订阅消息，验证模板字段与额度是否正确
                    res = service.wx.push_test()
                    self._json(res, HTTPStatus.OK if res.get("ok") else HTTPStatus.BAD_GATEWAY)
                else:
                    self._error(HTTPStatus.NOT_FOUND, f"未知接口：{path}")
            except json.JSONDecodeError:
                self._error(HTTPStatus.BAD_REQUEST, "请求体不是合法 JSON")
            except Exception as exc:
                self._json({"ok": False, "message": str(exc)}, HTTPStatus.INTERNAL_SERVER_ERROR)

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="0")
    parser.add_argument("--output", default="outputs")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-open", action="store_true")
    parser.add_argument("--ptz-backend", default="none", choices=["none", "onvif"])
    parser.add_argument("--ptz-host", default="")
    parser.add_argument("--ptz-port", type=int, default=80)
    parser.add_argument("--ptz-user", default="")
    parser.add_argument("--ptz-password", default="")
    parser.add_argument("--ptz-pan-gain", type=float, default=0.35)
    parser.add_argument("--ptz-tilt-gain", type=float, default=0.30)
    parser.add_argument("--ptz-dead-zone", type=float, default=0.12)
    parser.add_argument("--fourcc", default="auto",
                        help="录制编码：auto 自动探测浏览器可播的编码器，或指定 avc1/H264/VP80/mp4v 等")
    args = parser.parse_args()

    # --output 可能是相对路径，取决于启动时的 cwd。统一解析成绝对路径，
    # 否则 /files 列表会因为工作目录不同返回空。
    args.output = str(Path(args.output).resolve())

    ptz_config = PTZConfig(
        enabled=args.ptz_backend != "none",
        backend=args.ptz_backend,
        host=args.ptz_host,
        port=args.ptz_port,
        username=args.ptz_user,
        password=args.ptz_password,
        pan_gain=args.ptz_pan_gain,
        tilt_gain=args.ptz_tilt_gain,
        dead_zone=args.ptz_dead_zone,
    )
    service = CameraService(args.source, args.output, ptz_config, fourcc=args.fourcc)
    service.start()
    server = ThreadingHTTPServer((args.host, args.port), make_handler(service))
    url = f"http://{args.host}:{args.port}"
    print(f"Web 界面已启动：{url}")
    print(f"录制输出目录：{args.output}")
    print(f"录制编码：{service.record_codec}（容器 {service.record_ext}）")
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    finally:
        service.stop()


if __name__ == "__main__":
    main()
