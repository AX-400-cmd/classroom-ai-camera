"""媒体文件管理：列表、安全路径解析、Range 下载、删除、视频封面帧。

独立成模块的理由：web.py 已经很庞大，这些函数都是纯函数，便于单独验证。
"""

from __future__ import annotations

import json
import mimetypes
import time
from http import HTTPStatus
from pathlib import Path
from urllib.parse import quote

import cv2

ALLOWED_SUFFIX = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".jpg", ".jpeg", ".png"}
VIDEO_SUFFIX = {".mp4", ".mov", ".mkv", ".avi", ".webm"}
IMAGE_SUFFIX = {".jpg", ".jpeg", ".png"}

# 读文件的分块大小
_CHUNK = 65536


def is_allowed_name(name: str) -> bool:
    return Path(name).suffix.lower() in ALLOWED_SUFFIX


def safe_media_path(output_dir: str, name: str) -> Path | None:
    """把客户端传来的文件名解析成 output_dir 下的真实路径。

    三重防护（缺一不可）：
    1. 名字里不允许出现路径分隔符 / NUL / ..
    2. 后缀必须在白名单内
    3. resolve() 之后父目录必须等于 output_dir（防软链接穿越）
    """
    if not name:
        return None
    if "/" in name or "\\" in name or "\x00" in name:
        return None
    cand = Path(name)
    if cand.name != name or cand.is_absolute() or ".." in cand.parts:
        return None
    if cand.suffix.lower() not in ALLOWED_SUFFIX:
        return None
    base = Path(output_dir).resolve()
    try:
        target = (base / cand.name).resolve(strict=False)
    except OSError:
        return None
    if target.parent != base:
        return None
    if not target.is_file():
        return None
    return target


def list_media(output_dir: str, kind: str = "all", recording_name: str = "") -> list[dict]:
    """列出输出目录下的媒体文件，按修改时间倒序。只扫一层，跳过目录。"""
    base = Path(output_dir).resolve()
    if not base.is_dir():
        return []
    items: list[dict] = []
    for p in base.iterdir():
        if not p.is_file():  # 跳过 pip-temp / pytemp 之类的目录
            continue
        suffix = p.suffix.lower()
        if suffix not in ALLOWED_SUFFIX:
            continue
        file_kind = "video" if suffix in VIDEO_SUFFIX else "image"
        if kind not in ("all", "", None) and kind != file_kind:
            continue
        st = p.stat()
        items.append(
            {
                "name": p.name,
                "kind": file_kind,
                "size": st.st_size,
                "mtime": int(st.st_mtime),
                "modified": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime)),
                "recording": p.name == recording_name,
                "url": f"/files/download?name={quote(p.name)}",
                "poster": f"/files/poster?name={quote(p.name)}" if file_kind == "video" else None,
            }
        )
    items.sort(key=lambda x: x["mtime"], reverse=True)
    return items


def parse_range(header: str | None, size: int) -> tuple[int, int, bool]:
    """解析单区间 Range 头，返回 (start, end, ok)。ok=False 表示需要回 416。"""
    if not header or not header.lower().startswith("bytes="):
        return 0, max(size - 1, 0), True
    spec = header[6:].split(",")[0].strip()
    start_s, _, end_s = spec.partition("-")
    try:
        start = int(start_s) if start_s else 0
        end = int(end_s) if end_s else size - 1
    except ValueError:
        return 0, max(size - 1, 0), False
    end = min(end, size - 1)
    if start < 0 or start > end or start >= max(size, 1):
        return start, end, False
    return start, end, True


def write_file_response(handler, path: Path, disposition: str = "inline", body: bool = True) -> None:
    """写出文件响应，支持 HTTP Range（206），供 Chrome 拖动进度条。"""
    size = path.stat().st_size
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    start, end, ok = parse_range(handler.headers.get("Range"), size)
    if not ok:
        handler.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
        handler._cors()
        handler.send_header("Content-Range", f"bytes */{size}")
        handler.send_header("Content-Length", "0")
        handler.end_headers()
        return

    partial = not (start == 0 and end == size - 1)
    length = end - start + 1
    handler.send_response(HTTPStatus.PARTIAL_CONTENT if partial else HTTPStatus.OK)
    handler._cors()
    handler.send_header("Content-Type", mime)
    handler.send_header("Content-Length", str(length))
    handler.send_header("Accept-Ranges", "bytes")
    if partial:
        handler.send_header("Content-Range", f"bytes {start}-{end}/{size}")
    handler.send_header("Content-Disposition", f'{disposition}; filename="{path.name}"')
    handler.send_header("Cache-Control", "no-cache")
    handler.end_headers()

    if not body:  # HEAD 探测
        return
    with open(path, "rb") as fh:
        fh.seek(start)
        left = length
        while left > 0:
            chunk = fh.read(min(_CHUNK, left))
            if not chunk:
                break
            try:
                handler.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                return
            left -= len(chunk)


def poster_jpeg(path: Path, quality: int = 70) -> bytes | None:
    """取视频首帧做封面；失败返回 None（文件仍在写入或编码不受支持）。"""
    cap = cv2.VideoCapture(str(path))
    try:
        ok, frame = cap.read()
    finally:
        cap.release()
    if not ok or frame is None:
        return None
    ok_jpg, jpg = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), quality])
    if not ok_jpg:
        return None
    return jpg.tobytes()


def delete_media(output_dir: str, name: str) -> tuple[bool, str, HTTPStatus]:
    """删除单个媒体文件。返回 (ok, message, http_status)。"""
    target = safe_media_path(output_dir, name)
    if target is None:
        return False, "文件不存在或不允许删除", HTTPStatus.NOT_FOUND
    try:
        target.unlink()
    except PermissionError:
        return False, "文件被占用，无法删除（可能正在录制或被播放器占用）", HTTPStatus.CONFLICT
    except OSError as exc:
        return False, f"删除失败：{exc}", HTTPStatus.INTERNAL_SERVER_ERROR
    return True, f"已删除 {target.name}", HTTPStatus.OK


def read_json_body(handler) -> dict:
    """读取并解析 POST 的 JSON body，失败返回空字典。"""
    length = int(handler.headers.get("Content-Length", "0") or "0")
    if length <= 0:
        return {}
    raw = handler.rfile.read(length).decode("utf-8", errors="replace")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}
