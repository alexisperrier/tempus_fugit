import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from timetrack.db import connect
from timetrack.schema import init_schema


@pytest.fixture
def conn():
    db = connect(":memory:")
    init_schema(db)
    try:
        yield db
    finally:
        db.close()


def sample(ts, app="Zed", title="main.py — time_tracking", url=None, idle=False, bundle_id=None):
    return {"ts": ts, "app": app, "bundle_id": bundle_id, "title": title, "url": url, "idle": idle}
