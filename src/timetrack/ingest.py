"""Turn raw sampler JSONL (data/raw/*.jsonl) into merged `activities` rows.

Each line is one sample written by the menu bar app:
    {"ts": <epoch seconds>, "app": str, "bundle_id": str, "title": str|null,
     "url": str|null, "idle": bool, "interval": <seconds, optional>}

Consecutive samples with the same (app, bundle_id, title, url, idle) extend the
same activity while the gap between them stays under GAP_S. A larger gap
(sleep, lock, pause, app quit) closes the activity at its last sample.
Samples flagged idle (no input for 5 min) become idle activities, which are
excluded from working time.
"""
import json
import sqlite3
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

from timetrack import db

DEFAULT_INTERVAL_S = 5.0
GAP_S = 15.0
SAME_FIELDS = ("app", "bundle_id", "title", "url", "idle")


def to_iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch).isoformat(timespec="seconds")


def from_iso(value: str) -> float:
    return datetime.fromisoformat(value).timestamp()


def extract_domain(url: str | None) -> str | None:
    if not url:
        return None
    host = urlparse(url).hostname
    if not host:
        return None
    return host[4:] if host.startswith("www.") else host


def normalize(sample: dict) -> dict | None:
    if "ts" not in sample or not sample.get("app"):
        return None
    return {
        "ts": float(sample["ts"]),
        "app": sample["app"],
        "bundle_id": sample.get("bundle_id") or None,
        "title": sample.get("title") or None,
        "url": sample.get("url") or None,
        "idle": 1 if sample.get("idle") else 0,
        "interval": float(sample.get("interval") or DEFAULT_INTERVAL_S),
    }


def _last_activity(conn: sqlite3.Connection) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM activities ORDER BY end_ts DESC, id DESC LIMIT 1").fetchone()


def _same(activity: sqlite3.Row, sample: dict) -> bool:
    return all(activity[f] == sample[f] for f in SAME_FIELDS)


def ingest_samples(conn: sqlite3.Connection, samples: list[dict]) -> int:
    """Merge samples into activities. Returns the number of samples consumed."""
    consumed = 0
    current = _last_activity(conn)
    for raw in samples:
        sample = normalize(raw)
        if sample is None:
            continue
        consumed += 1
        ts = sample["ts"]
        sample_end = ts + sample["interval"]

        if current is not None:
            cur_end = from_iso(current["end_ts"])
            if ts < from_iso(current["start_ts"]):
                continue  # out-of-order / already ingested
            contiguous = ts - cur_end <= GAP_S
            if contiguous and _same(current, sample):
                new_end = max(cur_end, sample_end)
                conn.execute(
                    "UPDATE activities SET end_ts = ?, duration_s = ? WHERE id = ?",
                    (to_iso(new_end), new_end - from_iso(current["start_ts"]), current["id"]),
                )
                current = conn.execute("SELECT * FROM activities WHERE id = ?", (current["id"],)).fetchone()
                continue
            if contiguous and ts < cur_end:
                # Trim the previous activity so activities never overlap.
                conn.execute(
                    "UPDATE activities SET end_ts = ?, duration_s = ? WHERE id = ?",
                    (to_iso(ts), ts - from_iso(current["start_ts"]), current["id"]),
                )

        cur = conn.execute(
            """INSERT INTO activities (start_ts, end_ts, duration_s, app, bundle_id, title, url, domain, idle)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                to_iso(ts), to_iso(sample_end), sample["interval"], sample["app"], sample["bundle_id"],
                sample["title"], sample["url"], extract_domain(sample["url"]), sample["idle"],
            ),
        )
        current = conn.execute("SELECT * FROM activities WHERE id = ?", (cur.lastrowid,)).fetchone()
    return consumed


def _read_new_lines(conn: sqlite3.Connection, path: Path) -> list[dict]:
    row = conn.execute("SELECT byte_offset FROM ingest_state WHERE file = ?", (path.name,)).fetchone()
    offset = row["byte_offset"] if row else 0
    with path.open("rb") as fh:
        fh.seek(offset)
        chunk = fh.read()
    complete = chunk[: chunk.rfind(b"\n") + 1]  # ignore a partially written last line
    samples = []
    for line in complete.splitlines():
        try:
            samples.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    conn.execute(
        """INSERT INTO ingest_state (file, byte_offset) VALUES (?, ?)
           ON CONFLICT(file) DO UPDATE SET byte_offset = excluded.byte_offset""",
        (path.name, offset + len(complete)),
    )
    return samples


def ingest_raw_dir(conn: sqlite3.Connection, raw_dir: Path | None = None) -> dict:
    """Ingest new lines from every raw JSONL file."""
    raw_dir = db.RAW_DIR if raw_dir is None else raw_dir
    consumed = 0
    if raw_dir.exists():
        for path in sorted(raw_dir.glob("*.jsonl")):
            consumed += ingest_samples(conn, _read_new_lines(conn, path))
    conn.commit()
    return {"samples": consumed}
