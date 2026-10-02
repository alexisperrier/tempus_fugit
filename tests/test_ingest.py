import json
from datetime import datetime

from conftest import sample
from timetrack.ingest import extract_domain, ingest_raw_dir, ingest_samples

T0 = datetime(2026, 10, 2, 9, 0, 0).timestamp()


def _rows(conn):
    return conn.execute("SELECT * FROM activities ORDER BY start_ts").fetchall()


def test_consecutive_identical_samples_merge(conn):
    ingest_samples(conn, [sample(T0 + i * 5) for i in range(4)])
    rows = _rows(conn)
    assert len(rows) == 1
    assert rows[0]["duration_s"] == 20
    assert rows[0]["start_ts"] == "2026-10-02T09:00:00"
    assert rows[0]["end_ts"] == "2026-10-02T09:00:20"


def test_app_switch_starts_new_activity(conn):
    ingest_samples(conn, [sample(T0), sample(T0 + 5), sample(T0 + 10, app="Google Chrome", title="x", url="https://x.com/home")])
    rows = _rows(conn)
    assert [r["app"] for r in rows] == ["Zed", "Google Chrome"]
    assert rows[0]["duration_s"] == 10
    assert rows[1]["domain"] == "x.com"


def test_gap_splits_activity(conn):
    ingest_samples(conn, [sample(T0), sample(T0 + 5), sample(T0 + 600)])
    rows = _rows(conn)
    assert len(rows) == 2
    assert rows[0]["duration_s"] == 10
    assert rows[1]["duration_s"] == 5


def test_idle_flag_splits_activity(conn):
    ingest_samples(conn, [sample(T0), sample(T0 + 5, idle=True)])
    assert [r["idle"] for r in _rows(conn)] == [0, 1]


def test_extract_domain():
    assert extract_domain("https://www.youtube.com/watch?v=1") == "youtube.com"
    assert extract_domain("https://mail.google.com/mail/u/0") == "mail.google.com"
    assert extract_domain(None) is None
    assert extract_domain("about:blank") is None


def test_ingest_raw_dir_is_incremental_and_ignores_partial_lines(conn, tmp_path):
    path = tmp_path / "2026-10-02.jsonl"
    lines = [json.dumps(sample(T0 + i * 5)) for i in range(3)]
    path.write_text("\n".join(lines) + "\n" + '{"ts": 1, "app": "Pa')

    result = ingest_raw_dir(conn, tmp_path)
    assert result["samples"] == 3
    assert _rows(conn)[0]["duration_s"] == 15

    # Re-running reads nothing new.
    assert ingest_raw_dir(conn, tmp_path)["samples"] == 0

    # Completing the file keeps extending the open activity.
    with path.open("w") as fh:
        fh.write("\n".join(lines) + "\n" + json.dumps(sample(T0 + 15)) + "\n")
    # Rewrite changed the partial tail; offset points just past line 3.
    assert ingest_raw_dir(conn, tmp_path)["samples"] == 1
    rows = _rows(conn)
    assert len(rows) == 1
    assert rows[0]["duration_s"] == 20
