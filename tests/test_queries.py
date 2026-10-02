import sqlite3
from datetime import date, datetime

from conftest import sample
from status import build_status
from timetrack.classify import category
from timetrack.formatting import format_duration
from timetrack.ingest import ingest_samples
from timetrack.queries import activities_df, category_totals, totals_by
from timetrack.schema import init_schema

DAY = date(2026, 10, 2)
T0 = datetime(2026, 10, 2, 9, 0, 0).timestamp()


def _seed(conn):
    ingest_samples(conn, [
        sample(T0), sample(T0 + 5),
        sample(T0 + 10, app="Google Chrome", title="a", url="https://x.com/a"),
        sample(T0 + 15, app="VLC", title="movie.mkv"),
        sample(T0 + 20, app="Stremio", title="show"),
        sample(T0 + 25, idle=True),
    ])


def test_category_only_vlc_and_stremio_are_entertainment():
    assert category("VLC") == "entertainment"
    assert category("stremio") == "entertainment"
    assert category("Google Chrome") == "work"
    assert category("Zed") == "work"


def test_category_totals_and_idle(conn):
    _seed(conn)
    df = activities_df(conn, DAY, DAY, include_idle=True)
    assert category_totals(df) == {"work": 15, "entertainment": 10, "idle": 5}
    assert activities_df(conn, DAY, DAY)["duration_s"].sum() == 25
    assert activities_df(conn, date(2026, 10, 3), date(2026, 10, 3)).empty


def test_totals_by_app(conn):
    _seed(conn)
    by_app = totals_by(activities_df(conn, DAY, DAY), "app")
    assert by_app.iloc[0].to_dict()["app"] == "Zed"
    assert by_app.iloc[0].to_dict()["duration_s"] == 10


def test_build_status_shape(conn):
    assert set(build_status(conn)) == {"generated_at", "today_work_s"}


def test_legacy_schema_is_dropped_for_reingest():
    conn = sqlite3.connect(":memory:")
    conn.executescript("""
        CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE activities (id INTEGER PRIMARY KEY, project_id INTEGER);
        CREATE TABLE ingest_state (file TEXT PRIMARY KEY, byte_offset INTEGER);
        INSERT INTO ingest_state VALUES ('2026-10-02.jsonl', 999);
    """)
    init_schema(conn)
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    assert tables == {"activities", "ingest_state"}
    assert conn.execute("SELECT COUNT(*) FROM ingest_state").fetchone()[0] == 0


def test_format_duration():
    assert format_duration(15) == "15s"
    assert format_duration(42 * 60) == "42m"
    assert format_duration(3 * 3600 + 5 * 60) == "3h05"
