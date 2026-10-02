"""Read-side helpers returning pandas DataFrames for the Streamlit page and status."""
import sqlite3
from datetime import date, timedelta

import pandas as pd

from timetrack.classify import category


def activities_df(conn: sqlite3.Connection, start: date, end: date, include_idle: bool = False) -> pd.DataFrame:
    lo, hi = start.isoformat(), (end + timedelta(days=1)).isoformat()
    idle_clause = "" if include_idle else "AND idle = 0"
    df = pd.read_sql_query(
        f"SELECT * FROM activities WHERE start_ts >= ? AND start_ts < ? {idle_clause} ORDER BY start_ts",
        conn,
        params=(lo, hi),
    )
    df["category"] = df["app"].map(category)
    df.loc[df["idle"] == 1, "category"] = "idle"
    df["start"] = pd.to_datetime(df["start_ts"])
    df["end"] = pd.to_datetime(df["end_ts"])
    df["day"] = df["start"].dt.date
    return df


def totals_by(df: pd.DataFrame, column: str) -> pd.DataFrame:
    if df.empty:
        return pd.DataFrame(columns=[column, "duration_s", "hours"])
    out = df.groupby(column, dropna=False)["duration_s"].sum().reset_index().sort_values("duration_s", ascending=False)
    out["hours"] = out["duration_s"] / 3600
    return out.reset_index(drop=True)


def category_totals(df: pd.DataFrame) -> dict[str, float]:
    if df.empty:
        return {}
    return df.groupby("category")["duration_s"].sum().to_dict()


def today_work_seconds(conn: sqlite3.Connection) -> float:
    today = date.today()
    return float(category_totals(activities_df(conn, today, today)).get("work", 0.0))
