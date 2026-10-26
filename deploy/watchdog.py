# -*- coding: utf-8 -*-
"""无人值守守护进程：拉起 api_server，崩溃或卡死自动重启。

解决的问题：服务跑在教室里没人盯着，OpenCV 取流异常、摄像头被拔、
模型推理偶发报错都会让进程退出，没有守护就一直停到下课。

用法：
    py -3.12 deploy/watchdog.py --source 0 --host 0.0.0.0 --behavior ...

`--wd-*` 是守护自己的参数，其余参数原样透传给 api_server。
"""
from __future__ import annotations

import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LOG = ROOT / "work" / "watchdog.log"


def parse_own_args(argv: list[str]):
    """分离守护参数与透传参数。"""
    own = {"port": 8765, "log": str(DEFAULT_LOG), "max_fail": 5,
           "probe": True, "min_alive": 15.0}
    passthrough: list[str] = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--wd-port" and i + 1 < len(argv):
            own["port"] = int(argv[i + 1]); i += 2; continue
        if a == "--wd-log" and i + 1 < len(argv):
            own["log"] = argv[i + 1]; i += 2; continue
        if a == "--wd-max-fail" and i + 1 < len(argv):
            own["max_fail"] = int(argv[i + 1]); i += 2; continue
        if a == "--wd-min-alive" and i + 1 < len(argv):
            own["min_alive"] = float(argv[i + 1]); i += 2; continue
        if a == "--wd-no-probe":
            own["probe"] = False; i += 1; continue
        passthrough.append(a)
        i += 1
    # 透传参数里若显式指定了 --port，以它为准
    for j, a in enumerate(passthrough):
        if a == "--port" and j + 1 < len(passthrough):
            own["port"] = int(passthrough[j + 1])
    return own, passthrough


class Logger:
    def __init__(self, path: str):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.fp = self.path.open("a", encoding="utf-8")

    def __call__(self, msg: str):
        line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}"
        print(line, flush=True)
        try:
            self.fp.write(line + "\n")
            self.fp.flush()
        except OSError:
            pass

    def close(self):
        try:
            self.fp.close()
        except OSError:
            pass


def probe_health(port: int, timeout: float = 3.0) -> bool:
    """探活：/healthz 免鉴权，不泄露业务数据，适合守护调用。"""
    try:
        with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/healthz", timeout=timeout) as r:
            return r.status == 200
    except (urllib.error.URLError, OSError, ValueError):
        return False


def main():
    own, passthrough = parse_own_args(sys.argv[1:])
    log = Logger(own["log"])
    cmd = [sys.executable, "-u", "-m", "classroom_camera.api_server"] + passthrough
    log(f"守护启动：cwd={ROOT} cmd={' '.join(cmd[1:])}")
    log(f"探活端口 {own['port']}，连续快速失败上限 {own['max_fail']} 次")

    proc: subprocess.Popen | None = None
    started_at = 0.0
    quick_fails = 0
    miss_probe = 0
    last_probe = 0.0

    try:
        while True:
            # ---------- 子进程未运行：按退避策略重启 ----------
            if proc is None or proc.poll() is not None:
                if proc is not None:
                    code = proc.returncode
                    alive = time.monotonic() - started_at
                    log(f"服务退出（code={code}，存活 {alive:.1f}s）")
                    if alive < own["min_alive"]:
                        quick_fails += 1
                        log(f"快速失败计数 {quick_fails}/{own['max_fail']}"
                            f"（存活不足 {own['min_alive']:.0f}s，"
                            f"常见于摄像头未就绪/被占用/被拔）")
                    else:
                        quick_fails = 0
                    if quick_fails >= own["max_fail"]:
                        log("连续快速失败已达上限，停止重启。"
                            "请检查摄像头是否插好、端口是否被占用，"
                            "确认无误后重新运行本脚本。")
                        return 1
                    delay = min(300.0, 5.0 * (2 ** (quick_fails - 1)))
                    log(f"{delay:.0f}s 后重启")
                    time.sleep(delay)
                proc = subprocess.Popen(cmd, cwd=str(ROOT))
                started_at = time.monotonic()
                miss_probe = 0
                last_probe = 0.0
                log(f"服务已拉起（pid={proc.pid}）")
                time.sleep(8)  # 给摄像头与模型加载留出时间
                continue

            # ---------- 子进程在跑：定期探活，卡死也重启 ----------
            now = time.monotonic()
            if own["probe"] and now - last_probe >= 30.0:
                last_probe = now
                if probe_health(own["port"]):
                    miss_probe = 0
                else:
                    miss_probe += 1
                    log(f"探活失败 {miss_probe}/3")
                    if miss_probe >= 3:
                        log("连续 3 次探活失败，判定服务卡死，强制重启")
                        proc.terminate()
                        try:
                            proc.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            proc.kill()
                        proc = None
                        continue
            time.sleep(1.0)
    except KeyboardInterrupt:
        log("收到 Ctrl+C，正在停止服务")
        if proc and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
        log("守护已停止")
        return 0
    finally:
        log.close()


if __name__ == "__main__":
    sys.exit(main())
