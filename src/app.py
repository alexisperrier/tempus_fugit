import altair as alt
import streamlit as st

from timetrack.classify import ENTERTAINMENT_APPS
from timetrack.formatting import format_duration
from timetrack.queries import activities_df, category_totals, totals_by
from timetrack.ui import CATEGORY_COLORS, date_range_picker, open_db

st.set_page_config(page_title="TimeTrack", layout="wide")
st.title("TimeTrack")
st.caption(
    f"Entertainment apps: {', '.join(sorted(ENTERTAINMENT_APPS))}. Everything else is work. "
    "No input for 5 min counts as idle (not work)."
)

conn = open_db()
start, end = date_range_picker("main")
df = activities_df(conn, start, end, include_idle=True)
conn.close()

if df.empty:
    st.info("No activity recorded for this period yet. Start the menu bar app with `make menu-restart`.")
    st.stop()

cats = category_totals(df)
active = df[df["category"] != "idle"]
c1, c2, c3 = st.columns(3)
c1.metric("Work", format_duration(cats.get("work", 0)))
c2.metric("Entertainment", format_duration(cats.get("entertainment", 0)))
c3.metric("Idle", format_duration(cats.get("idle", 0)))

category_scale = alt.Scale(domain=list(CATEGORY_COLORS), range=list(CATEGORY_COLORS.values()))

days = sorted(df["day"].unique())
if len(days) > 1:
    st.subheader("Per day")
    daily = active.groupby(["day", "category"])["duration_s"].sum().reset_index()
    daily["hours"] = daily["duration_s"] / 3600
    daily["day"] = daily["day"].astype(str)
    st.altair_chart(
        alt.Chart(daily).mark_bar().encode(
            x=alt.X("day:N", title=None),
            y=alt.Y("hours:Q", title="Hours"),
            color=alt.Color("category:N", scale=category_scale),
            tooltip=["day", "category", alt.Tooltip("hours:Q", format=".2f")],
        ),
        width="stretch",
    )

st.subheader("Timeline")
day = st.selectbox("Day", days, index=len(days) - 1, format_func=str, key="timeline_day") if len(days) > 1 else days[0]
day_df = df[df["day"] == day].copy()
day_df["what"] = day_df["domain"].fillna(day_df["title"]).fillna("")
day_df["time"] = day_df["duration_s"].map(format_duration)
st.altair_chart(
    alt.Chart(day_df).mark_bar(height=14).encode(
        x=alt.X("start:T", title=None),
        x2="end:T",
        y=alt.Y("app:N", title=None, sort=alt.EncodingSortField("duration_s", op="sum", order="descending")),
        color=alt.Color("category:N", scale=category_scale),
        tooltip=["app", "what", "category", "time", alt.Tooltip("start:T", format="%H:%M")],
    ),
    width="stretch",
)


def _table(frame, column, label):
    out = totals_by(frame, column)
    out["time"] = out["duration_s"].map(format_duration)
    out["share"] = out["duration_s"] / out["duration_s"].sum()
    st.dataframe(
        out[[column, "time", "share"]],
        hide_index=True,
        width="stretch",
        column_config={
            column: st.column_config.TextColumn(label, width="large"),
            "share": st.column_config.ProgressColumn("Share", format="percent", min_value=0, max_value=1),
        },
    )


left, right = st.columns(2)
with left:
    st.subheader("Apps")
    _table(active, "app", "App")
with right:
    st.subheader("Websites")
    sites = active[active["domain"].notna()]
    if sites.empty:
        st.caption("No browser URLs recorded (Chrome only; Firefox shows up by window title below).")
    else:
        _table(sites, "domain", "Domain")

st.subheader("Drill down")
apps = totals_by(active, "app")["app"].tolist()
if apps:
    app = st.selectbox("App", apps, key="drill_app")
    app_df = active[active["app"] == app]
    d1, d2 = st.columns(2)
    with d1:
        st.markdown("**Window titles**")
        _table(app_df.assign(title=app_df["title"].fillna("(no title)")), "title", "Title")
    with d2:
        if app_df["url"].notna().any():
            st.markdown("**URLs**")
            _table(app_df[app_df["url"].notna()], "url", "URL")
