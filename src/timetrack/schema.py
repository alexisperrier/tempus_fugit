import sqlite3

SCHEMA = """
CREATE TABLE IF NOT EXISTS activities (
    id INTEGER PRIMARY KEY,
    start_ts TEXT NOT NULL,
    end_ts TEXT NOT NULL,
    duration_s REAL NOT NULL,
    app TEXT NOT NULL,
    bundle_id TEXT,
    title TEXT,
    url TEXT,
    domain TEXT,
    idle INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_activities_start ON activities(start_ts);

CREATE TABLE IF NOT EXISTS ingest_state (
    file TEXT PRIMARY KEY,
    byte_offset INTEGER NOT NULL DEFAULT 0
);
"""

LEGACY_TABLES = ("projects", "category_rules", "project_rules", "meta")


def init_schema(conn: sqlite3.Connection) -> None:
    drop_legacy_schema(conn)
    conn.executescript(SCHEMA)
    conn.commit()


def drop_legacy_schema(conn: sqlite3.Connection) -> None:
    """The project/rules era stored derived data; drop it and re-ingest from raw samples."""
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if not tables & set(LEGACY_TABLES):
        return
    for table in ("activities", "ingest_state", *LEGACY_TABLES):
        conn.execute(f"DROP TABLE IF EXISTS {table}")
    conn.commit()
