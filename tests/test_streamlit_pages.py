import json
from datetime import datetime
from pathlib import Path

import pytest
from streamlit.testing.v1 import AppTest

from conftest import sample
from timetrack import db

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "DB_PATH", tmp_path / "timetrack.db")
    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    return tmp_path


def _write_samples(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    now = datetime.now().replace(hour=9, minute=0, second=0, microsecond=0).timestamp()
    lines = [sample(now + i * 5) for i in range(6)]
    lines += [sample(now + 30 + i * 5, app="Google Chrome", title="Inbox", url="https://mail.google.com/") for i in range(3)]
    lines += [sample(now + 45 + i * 5, app="VLC", title="movie") for i in range(3)]
    lines += [sample(now + 60, idle=True)]
    (raw / "today.jsonl").write_text("\n".join(json.dumps(s) for s in lines) + "\n")


def test_app_runs_empty(env):
    app = AppTest.from_file(str(ROOT / "src/app.py")).run(timeout=10)
    assert not app.exception


def test_app_runs_with_data(env):
    _write_samples(env)
    app = AppTest.from_file(str(ROOT / "src/app.py")).run(timeout=10)
    assert not app.exception
    assert [m.value for m in app.metric] == ["45s", "15s", "5s"]
