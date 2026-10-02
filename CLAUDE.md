# TimeTrack

Personal macOS activity tracker. Stack: uv + Python 3.11, plain sqlite3 (no ORM), Streamlit, Makefile, native Swift menu bar app compiled with `swiftc` (no Xcode project).

Full design reference: `docs/SPEC.md` (keep it in sync when behaviour changes). Kept deliberately simple: no projects, no rules. Entertainment = apps in `timetrack/classify.py` `ENTERTAINMENT_APPS` (VLC, Stremio); everything else is work. Idle (no input ≥ 5 min, detected by the sampler) is never work. Category is computed at query time, so editing the list needs no migration.

## Data flow
1. `macos/TimeTrackMenu` (Swift) samples every 5 s and appends JSON lines to `data/raw/YYYY-MM-DD.jsonl` (`ts` epoch, `app`, `bundle_id`, `title`, `url`, `idle`, `interval`). It never touches SQLite.
2. `src/timetrack/ingest.py` reads new bytes per file (`ingest_state` offsets) and merges identical consecutive samples into `activities`. A gap over 15 s splits an activity.
3. Streamlit (`src/app.py`, single page, port 8600, bound to 127.0.0.1 via `.streamlit/config.toml`) and `src/status.py` (`make -s status`, polled by the menu every 60 s) both ingest before reading.

## Conventions
- Business logic in `src/timetrack/`; UI only in `src/app.py`.
- Timestamps in `activities` are local naive ISO strings.
- `data/raw` is the source of truth; the DB can always be rebuilt (`make reset-db`). `schema.drop_legacy_schema` drops the old project/rules tables and re-ingests.
- Run `make test` before handing off. The page is smoke-tested via `streamlit.testing.v1.AppTest` with `db.DB_PATH`/`db.RAW_DIR` monkeypatched.
