from pathlib import Path
from datetime import datetime
import os
import threading

import cv2

# 按“浏览器能播”的优先级排列。mp4v 实际会写成 MPEG-4 Part 2（fourcc 显示 FMP4），
# Chrome 的 <video> 不支持，因此放在最后兜底。
_ENCODER_CANDIDATES = (
    ("avc1", ".mp4"),   # H.264，Chrome/Safari 原生支持
    ("H264", ".mp4"),
    ("X264", ".mp4"),
    ("VP09", ".webm"),  # VP9
    ("VP80", ".webm"),  # VP8
    ("mp4v", ".mp4"),
)

# OpenCV 在 Windows 上遇到含非 ASCII 字符（如中文）的路径时，VideoWriter / imwrite
# 会静默失败（isOpened() 为 False、imwrite 返回 False），但 VideoCapture 读取正常。
# 规避办法：写文件前 chdir 到目标目录，只用纯文件名打开，再切回原工作目录。
_cv2_lock = threading.Lock()


def _with_cwd(directory: Path, action):
    """在 directory 下执行 action（action 内部只使用纯文件名），结束后切回原目录。"""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    previous = os.getcwd()
    with _cv2_lock:
        try:
            os.chdir(str(directory))
            return action()
        finally:
            os.chdir(previous)


def open_video_writer(directory, filename: str, fourcc: str, fps: float, size: tuple[int, int]):
    """在 directory 下创建 VideoWriter，绕开 OpenCV 非 ASCII 路径问题。"""
    return _with_cwd(
        Path(directory),
        lambda: cv2.VideoWriter(filename, cv2.VideoWriter_fourcc(*fourcc), fps, size),
    )


def imwrite_safe(path: Path, image) -> bool:
    """cv2.imwrite 的非 ASCII 路径安全版本。"""
    path = Path(path)
    return _with_cwd(path.parent, lambda: cv2.imwrite(path.name, image))


def pick_encoder(output_dir: str, requested: str = "auto", size: tuple[int, int] = (640, 480)):
    """挑一个可用的录制编码器，返回 (fourcc, 扩展名)。

    requested 为 "auto" 时按顺序探测；否则直接使用用户指定的四字符编码。
    探测必须用与真实录制完全相同的方式（open_video_writer）——否则在中文路径下
    探测会误判 avc1 不可用，从而选到 VP09。
    """
    if requested and requested.lower() != "auto":
        ext = ".webm" if requested in ("VP80", "VP09", "VP90") else ".mp4"
        return requested, ext

    import numpy as np

    base = Path(output_dir)
    for code, ext in _ENCODER_CANDIDATES:
        probe_name = f"_probe_{code}{ext}"
        probe = base / probe_name
        writer = None
        try:
            writer = open_video_writer(base, probe_name, code, 20.0, size)
            if writer.isOpened():
                writer.write(np.zeros((size[1], size[0], 3), np.uint8))
                writer.release()
                writer = None
                if probe.exists() and probe.stat().st_size > 0:
                    probe.unlink(missing_ok=True)
                    return code, ext
        except Exception:
            pass
        finally:
            if writer is not None:
                try:
                    writer.release()
                except Exception:
                    pass
        probe.unlink(missing_ok=True)
    return "mp4v", ".mp4"


class CameraCapture:
    def __init__(self, source: str, output_dir: str, width: int = 0, height: int = 0):
        self.source = int(source) if source.isdigit() else source
        self.output_dir = Path(output_dir)
        self.cap = None
        self.writer = None
        # 0 表示不改分辨率（保持摄像头默认，目前是 640x480）。
        # 行为检测建议显式设 1280x720：推理输入仍是 640，但源更清晰，
        # 远处小目标（手机）的置信度会明显提升。
        self.width = width
        self.height = height

    def open(self) -> None:
        self.cap = cv2.VideoCapture(self.source)
        if not self.cap.isOpened():
            raise RuntimeError(f"无法打开摄像头或视频源：{self.source}")
        if self.width > 0:
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        if self.height > 0:
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)

    def read(self):
        if self.cap is None:
            return False, None
        ok, frame = self.cap.read()
        if ok and self.writer is not None:
            self.writer.write(frame)
        return ok, frame

    def start_recording(self, frame_size: tuple[int, int], fps: float = 20.0,
                        fourcc: str = "mp4v", ext: str = ".mp4") -> Path:
        self.output_dir.mkdir(parents=True, exist_ok=True)
        path = self.output_dir / f"class_{datetime.now():%Y%m%d_%H%M%S}{ext}"
        width, height = frame_size
        self.writer = open_video_writer(self.output_dir, path.name, fourcc, fps, (width, height))
        if not self.writer.isOpened():
            self.writer = None
            raise RuntimeError(f"无法创建录制文件（编码 {fourcc}），请检查 OpenCV 编解码器。")
        return path

    def stop_recording(self) -> None:
        if self.writer is not None:
            self.writer.release()
            self.writer = None

    def close(self) -> None:
        self.stop_recording()
        if self.cap is not None:
            self.cap.release()
            self.cap = None
