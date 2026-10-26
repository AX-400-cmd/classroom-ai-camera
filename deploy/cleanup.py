# -*- coding: utf-8 -*-
"""容量清理：删除过期的录像、留证截图与统计记录。

跑一个学期后 outputs/ 会一直涨（录像按 GB 计），SQLite 也会变大。
这个脚本按"保留天数"清理，**默认只演练不删除**，确认无误后加 --apply 才真删。

用法：
    py -3.12 deploy/cleanup.py                 # 演练，打印将删除什么
    py -3.12 deploy/cleanup.py --days 30 --apply
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# 录像与截图扩展名（与 media.py / behavior.py 的产出保持一致）
MEDIA_EXT = {".mp4", ".avi", ".mkv", ".mov", ".webm"}
IMAGE_EXT = {".jpg", ".jpeg", ".png"}


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def main():
    root_default = str(ROOT / "outputs")
    ap = argparse.ArgumentParser(description="清理过期的录像、截图与统计记录")
    ap.add_argument("--days", type=int, default=30, help="保留最近 N 天，默认 30")
    ap.add_argument("--outputs", default=root_default, help="录制与截图输出目录")
    ap.add_argument("--db", default="", help="stats.db 路径，默认取 outputs 下的")
    ap.add_argument("--apply", action="store_true", help="真正执行删除（不加则只演练）")
    args = ap.parse_args()

    outputs = Path(args.outputs).resolve()
    db_path = Path(args.db).resolve() if args.db else outputs / "stats.db"
    cutoff = time.time() - args.days * 86400
    cutoff_text = time.strftime("%Y-%m-%d %H:%M", time.localtime(cutoff))

    print(f"输出目录：{outputs}")
    print(f"保留最近 {args.days} 天（早于 {cutoff_text} 的内容将被清理）")
    print(f"模式：{'实际删除' if args.apply else '演练（不会删任何东西）'}")
    print("-" * 60)

    if not outputs.exists():
        print(f"目录不存在：{outputs}")
        return 1

    # ---------- 1) 文件 ----------
    targets: list[tuple[Path, int]] = []
    for path in outputs.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in MEDIA_EXT and path.suffix.lower() not in IMAGE_EXT:
            continue
        # 安全阀：只处理输出目录内的文件
        if outputs not in path.parents and path.parent != outputs:
            continue
        try:
            mtime = path.stat().st_mtime
            size = path.stat().st_size
        except OSError:
            continue
        if mtime < cutoff:
            targets.append((path, size))

    total = sum(s for _, s in targets)
    print(f"过期文件 {len(targets)} 个，合计 {human(total)}")
    for path, size in targets[:20]:
        print(f"  {human(size):>10}  {path.relative_to(outputs)}")
    if len(targets) > 20:
        print(f"  ... 其余 {len(targets) - 20} 个略")

    # ---------- 2) 数据库记录 ----------
    db_rows = 0
    if db_path.exists():
        try:
            conn = sqlite3.connect(str(db_path))
            n_sample = conn.execute(
                "SELECT COUNT(*) FROM sample WHERE ts < ?", (int(cutoff),)).fetchone()[0]
            n_alert = conn.execute(
                "SELECT COUNT(*) FROM alert WHERE ts < ?", (int(cutoff),)).fetchone()[0]
            db_rows = n_sample + n_alert
            print(f"\n过期统计记录：sample {n_sample} 条，alert {n_alert} 条")
            if args.apply and db_rows:
                conn.execute("DELETE FROM sample WHERE ts < ?", (int(cutoff),))
                conn.execute("DELETE FROM alert WHERE ts < ?", (int(cutoff),))
                conn.commit()
                conn.execute("VACUUM")   # 删完回收磁盘空间
                conn.commit()
                print("  已删除并 VACUUM")
            conn.close()
        except sqlite3.Error as exc:
            print(f"\n数据库处理失败（不影响文件清理）：{exc}")
    else:
        print(f"\n未找到统计数据库：{db_path}")

    # ---------- 3) 执行删除 ----------
    print("-" * 60)
    if not args.apply:
        print(f"演练结束。确认无误后重跑并加 --apply，可释放约 {human(total)}。")
        return 0
    deleted = 0
    freed = 0
    for path, size in targets:
        try:
            path.unlink()
            deleted += 1
            freed += size
        except OSError as exc:
            print(f"  删除失败：{path}（{exc}）")
    print(f"已删除 {deleted} 个文件，释放 {human(freed)}；数据库记录 {db_rows} 条。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
