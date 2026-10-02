"""Small Streamlit helpers."""
from datetime import date, timedelta

import streamlit as st

from timetrack.db import connect
from timetrack.ingest import ingest_raw_dir
from timetrack.schema import init_schema

# Colour-blind-safe work/entertainment pair (blue vs orange), validated for
# protan/deutan/tritan separation on each surface. Idle is a neutral gray on purpose.
CATEGORY_COLORS = {
    "light": {"work": "#2a78d6", "entertainment": "#eb6834", "idle": "#8f8e89"},
    "dark": {"work": "#3987e5", "entertainment": "#d95926", "idle": "#8f8e89"},
}


def category_colors() -> dict[str, str]:
    """Palette for the active Streamlit theme (light unless the viewer is in dark mode)."""
    try:
        mode = st.context.theme.type
    except Exception:
        mode = None
    return CATEGORY_COLORS["dark" if mode == "dark" else "light"]


RANGE_PRESETS = ["Today", "Yesterday", "Last 7 days", "This month", "Custom"]


def open_db():
    """Connect, ensure schema, and pull in any new sampler data."""
    conn = connect()
    init_schema(conn)
    ingest_raw_dir(conn)
    return conn


def date_range_picker(key: str) -> tuple[date, date]:
    today = date.today()
    cols = st.columns([2, 3])
    preset = cols[0].selectbox("Period", RANGE_PRESETS, key=f"{key}_preset")
    if preset == "Today":
        return today, today
    if preset == "Yesterday":
        y = today - timedelta(days=1)
        return y, y
    if preset == "Last 7 days":
        return today - timedelta(days=6), today
    if preset == "This month":
        return today.replace(day=1), today
    picked = cols[1].date_input("Range", (today - timedelta(days=6), today), key=f"{key}_range")
    if isinstance(picked, (tuple, list)):
        if len(picked) == 2:
            return picked[0], picked[1]
        if len(picked) == 1:
            return picked[0], picked[0]
    return picked, picked
