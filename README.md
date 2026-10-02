# TimeTrack

A local macOS time tracker for personal use. A menu bar app samples the frontmost app, window title and Chrome URL every 5 s. The menu bar shows how long you've worked today, and a one-page Streamlit app breaks the time down by app and website.

Rules:
- **Entertainment** = VLC and Stremio (`src/timetrack/classify.py`). **Everything else is work.**
- **Idle**: with no keyboard or mouse input for 5 min, you're considered to have stopped working. Idle time is recorded but never counted as work.
- Screen lock, sleep and Pause stop sampling entirely.

**Setting it up on another Mac: see [SETUP.md](SETUP.md). Design and decisions: [docs/SPEC.md](docs/SPEC.md).**

Everything stays on this Mac: `data/raw/*.jsonl` (raw samples, source of truth) and `data/timetrack.db` (SQLite, rebuilt from raw at any time).

## Quick start

```bash
uv sync
make menu-restart   # build + launch the menu bar app (starts sampling)
make app            # Streamlit at http://localhost:8600 (local only)
```

## Permissions (first launch)

- **Accessibility** (window titles): System Settings → Privacy & Security → Accessibility → enable `TimeTrackMenu`.
- **Automation → Google Chrome** (tab URL): macOS asks the first time Chrome is frontmost. Click Allow.
- Firefox has no scripting API for URLs, so it is tracked by window title.

### Keep permissions across rebuilds (one-time)

macOS ties these permissions to the code signature, and an ad-hoc signature changes on every build: the toggle in System Settings stays on but no longer applies. Fix it once from the CLI:

```bash
make menu-signing             # creates the self-signed "TimeTrack Dev" identity in the login keychain
make menu-reset-permissions   # clears the stale grants (tccutil)
make menu-restart             # rebuilt + signed with the stable identity
```

Then enable TimeTrackMenu in Accessibility one last time. macOS doesn't allow that toggle to be set from the CLI. Later rebuilds keep the permission.

## Commands

| Command | What it does |
|---|---|
| `make app` / `make stop` | start / stop Streamlit (port 8600) |
| `make menu-restart` / `make menu-stop` | rebuild + relaunch / quit the menu bar app |
| `make ingest` | merge new raw samples into SQLite (also runs on page load and status) |
| `make status` | ingest, then print today's working time as JSON (what the menu shows) |
| `make test` | pytest |
| `make reset-db` | rebuild the DB from raw samples |
