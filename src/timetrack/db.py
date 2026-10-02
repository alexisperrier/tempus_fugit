import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = ROOT / "data"
DB_PATH = DATA_DIR / "timetrack.db"
RAW_DIR = DATA_DIR / "raw"


def connect(db_path: Path | str | None = None) -> sqlite3.Connection:
    """Open a TimeTrack SQLite connection with consistent defaults."""
    path = DB_PATH if db_path is None else db_path
    if path != ":memory:":
        Path(path).parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn
