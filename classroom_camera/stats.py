"""课堂统计持久化层。

把行为告警与「人数 / 注意力人数」采样落盘到 SQLite，供日报 / 周报聚合使用。
放在独立模块、不侵入 behavior.py，避免影响既有的告警 / 通知链路。

设计要点：
- 告警表以 `id` 为主键，`INSERT OR IGNORE` 天然去重（增量游标之外的第二道防线）。
- 采样表按秒落一条，写入端用 5s 节流；一天约 1.7 万条，SQLite 完全扛得住。
- 仅用标准库 sqlite3，不依赖 torch / ultralytics，可离线单测。
"""

from __future__ import annotations

import sqlite3
import threading
import time
from datetime import datetime
from pathlib import Path


class StatsStore:
    """SQLite 封装：告警 + 人数采样 + 聚合查询。"""

    def __init__(self, db_path: str | Path):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        # 跨线程（采集线程写、HTTP 线程读）共用一个连接，用锁保护。
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(str(self.db_path), check_same_thread=False)
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._init_schema()

    def _init_schema(self) -> None:
        with self._lock:
            self._conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS sample (
                    ts        INTEGER NOT NULL,
                    persons   INTEGER NOT NULL,
                    attention INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS alert (
                    ts        INTEGER NOT NULL,
                    id        TEXT PRIMARY KEY,
                    detail    TEXT,
                    track_id  INTEGER,
                    seconds   REAL,
                    score     REAL,
                    evidence  TEXT,
                    snapshot  TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_sample_ts ON sample(ts);
                CREATE INDEX IF NOT EXISTS idx_alert_ts  ON alert(ts);
                """
            )

    # ===================== 写入 =====================
    def record_sample(self, persons: int, attention: int) -> None:
        """写入一条人数采样。失败时静默跳过，绝不拖垮主服务。"""
        now = int(time.time())
        try:
            with self._lock:
                self._conn.execute(
                    "INSERT INTO sample(ts, persons, attention) VALUES(?,?,?)",
                    (now, int(persons), int(attention)),
                )
                self._conn.commit()
        except Exception:
            pass

    def record_alert(self, ev) -> bool:
        """写入一条告警；主键冲突（同 id）则忽略。返回是否新增。"""
        try:
            with self._lock:
                cur = self._conn.execute(
                    "INSERT OR IGNORE INTO alert"
                    "(ts, id, detail, track_id, seconds, score, evidence, snapshot) "
                    "VALUES(?,?,?,?,?,?,?,?)",
                    (
                        int(ev.ts),
                        ev.id,
                        getattr(ev, "detail", "attention"),
                        getattr(ev, "track_id", 0),
                        getattr(ev, "seconds", 0.0),
                        getattr(ev, "score", 0.0),
                        getattr(ev, "evidence", ""),
                        getattr(ev, "snapshot", ""),
                    ),
                )
                self._conn.commit()
                return cur.rowcount > 0
        except Exception:
            return False

    # ===================== 读取 =====================
    def _range_bounds(self, range_: str) -> tuple[int, int]:
        now = int(time.time())
        if range_ == "day":
            start = int(
                datetime.now()
                .replace(hour=0, minute=0, second=0, microsecond=0)
                .timestamp()
            )
            return start, now
        if range_ == "week":
            return now - 7 * 86400, now
        return 0, now  # all

    def summary(self, range_: str = "day") -> dict:
        start, end = self._range_bounds(range_)
        with self._lock:
            rows = self._conn.execute(
                "SELECT ts, detail, seconds FROM alert WHERE ts>=? AND ts<=?",
                (start, end),
            ).fetchall()
            samples = self._conn.execute(
                "SELECT persons, attention FROM sample WHERE ts>=? AND ts<=?",
                (start, end),
            ).fetchall()

        alert_total = len(rows)
        total_seconds = sum((r[2] or 0.0) for r in rows)
        by_detail: dict[str, int] = {"phone": 0, "sleep": 0, "attention": 0}
        by_hour = [0] * 24
        for r in rows:
            detail = r[1] or "attention"
            by_detail[detail] = by_detail.get(detail, 0) + 1
            by_hour[datetime.fromtimestamp(r[0]).hour] += 1

        persons_list = [s[0] for s in samples]
        att_list = [s[1] for s in samples]
        persons_max = max(persons_list) if persons_list else 0
        persons_avg = (
            round(sum(persons_list) / len(persons_list), 1) if persons_list else 0
        )
        attention_avg = (
            round(sum(att_list) / len(att_list), 2) if att_list else 0
        )
        top_hour = max(range(24), key=lambda h: by_hour[h]) if alert_total else -1

        return {
            "range": range_,
            "start": start,
            "end": end,
            "alert_total": alert_total,
            "alert_total_seconds": round(total_seconds, 1),
            "by_detail": by_detail,
            "by_hour": by_hour,
            "persons_max": persons_max,
            "persons_avg": persons_avg,
            "attention_avg": attention_avg,
            "top_hour": top_hour,
            "sample_count": len(samples),
        }

    def close(self) -> None:
        try:
            with self._lock:
                self._conn.close()
        except Exception:
            pass
