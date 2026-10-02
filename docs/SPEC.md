# TimeTrack: specification

This is the design reference. It covers what the system does, the contracts between its parts, the algorithms, and why it is shaped this way. Installation steps are in [SETUP.md](../SETUP.md).

## 1. Purpose and scope

TimeTrack answers one question for one person on one Mac: **how much did I actually work today, and where did the time go?**

**Goals**
- Fully automatic. Nothing to start, stop or tag during the day.
- Fully local. No account, no server, no telemetry.
- Glanceable: today's work time is always visible in the menu bar.
- Reviewable: per-app, per-website and per-window-title breakdowns, plus a daily timeline.
- Rebuildable: raw observations are kept, so any derived number can be recomputed when the logic changes.

**Non-goals** (deliberately out of scope)
- Client billing, invoicing, or assigning time to projects. These were built and then removed; see §10.
- Multi-device sync, teams, or cloud storage.
- Productivity scoring beyond a binary work / entertainment split.
- Keystroke or screen-content capture. Only app name, window title and Chrome URL are recorded.

## 2. Classification rules

| Category | Definition |
|---|---|
| **entertainment** | The frontmost app is in `ENTERTAINMENT_APPS` = {`vlc`, `stremio`}, matched case-insensitively on the app name. |
| **work** | Any other app. This includes all browsers and websites. |
| **idle** | The sample was flagged idle: no keyboard, mouse or trackpad input for ≥ `idleMinutes` (default 5). Idle beats both other categories. |
| *(not recorded)* | Paused, screen locked, or asleep. No samples are written. |

- **"Worked today"** is the sum of `work` durations for activities starting today.
- **Classification happens at query time, not ingest time.** Editing `src/timetrack/classify.py` therefore re-classifies all history instantly, with no migration or re-ingest.
- **Known consequence:** websites are always work, including x.com and YouTube in Chrome. A domain list would be the natural extension (§11).
- **Idle semantics:** the first `idleMinutes` of inactivity are still counted as work, because the sampler can't know in advance that you've stopped. From the moment the threshold is crossed, samples are idle until input resumes. A movie in VLC with no input therefore becomes idle after 5 min, not entertainment.

## 3. Architecture

```
┌──────────────────────── macOS host ─────────────────────────────────────────┐
│                                                                             │
│  TimeTrackMenu.app (Swift)                                                  │
│   ├─ Sampler ──every 5 s──▶ data/raw/YYYY-MM-DD.jsonl   (append-only)       │
│   └─ StatusModel ─every 60 s─▶ `make -s status` ──▶ JSON ──▶ "⏱ 3h12"       │
│                                        │                                    │
│                                        ▼                                    │
│                         src/timetrack/ingest.py ──▶ data/timetrack.db       │
│                                        ▲                (SQLite, derived)   │
│  Streamlit src/app.py (127.0.0.1:8600) ┘  ingests on every page load        │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key boundaries**
- **The Swift app writes the raw log only.** It never opens SQLite, and it talks to Python solely by running `make -s <target>` and decoding stdout JSON. This keeps the Swift side tiny and keeps every rule in Python, where it is testable.
- **Raw JSONL is the source of truth.** The DB is a cache that `make reset-db` can always rebuild.
- **There is no background Python daemon.** Ingestion is lazy: it runs when the menu polls status (every 60 s) and when the dashboard loads.

**Stack**

| Layer | Choice | Why |
|---|---|---|
| Python env | uv, Python 3.11 | One command (`uv sync`), and it pins its own Python. |
| Storage | Plain `sqlite3`, no ORM | Two tables. Migrations are hand-written in `schema.py`. |
| UI | Streamlit + Altair, one page | Quickest way to get a local, interactive dashboard. |
| Menu app | SwiftUI + AppKit, compiled with `swiftc` | Native APIs (Accessibility, AppleScript, idle time), tiny footprint, no Xcode project. |
| Orchestration | Makefile | A single entry point for humans and for the menu app. |
| Containers | None | The sampler must run on the host, since containers can't see macOS windows, so Docker would add nothing. |

## 4. Components

### 4.1 Sampler (`macos/TimeTrackMenu/src/Sampler.swift`)

On each tick (default every 5 s, timer tolerance 0.5 s) the sampler does the following:

1. **Skip the tick** and expose the reason in the UI if any of these hold:
   - paused (`data/paused` exists)
   - screen locked (distributed notifications `com.apple.screenIsLocked` / `…Unlocked`)
   - asleep (`NSWorkspace` `willSleep` / `screensDidSleep` / `didWake` / `screensDidWake`)
2. **Front app:** `NSWorkspace.shared.frontmostApplication` gives `localizedName` and `bundleIdentifier`.
3. **Window title:** `AXUIElementCreateApplication(pid)` → `kAXFocusedWindowAttribute` → `kAXTitleAttribute`. This needs the Accessibility permission; without it, the title is null.
4. **URL:** only if the bundle ID has an entry in `urlScripts` (currently only `com.google.Chrome`). The sampler runs `NSAppleScript` with `get URL of active tab of front window`, which needs the Automation permission. Error −1728 ("no window") is silently ignored.
5. **Private apps** (`privateApps`, default `1Password, Keychain Access`): the title and URL are never read, only the app name is recorded.
6. **Idle:** `CGEventSource.secondsSinceLastEventType(.combinedSessionState, anyInputEventType) ≥ idleMinutes × 60`.
7. **Write:** append one JSON line to `data/raw/<local date>.jsonl`, creating the directory or file if needed.

**Settings** are stored in `UserDefaults` under the bundle ID: `sampleSeconds` (5), `idleMinutes` (5), `privateApps`. The repo path is not a setting: `build.sh` bakes it into `Info.plist` as `TimeTrackRepoPath`, with a fallback of three levels above the `.app`.

**Cost:** one Accessibility call per tick, plus one AppleScript call while Chrome is frontmost. The raw log grows by roughly 1 MB per 8 h of activity.

### 4.2 Ingest (`src/timetrack/ingest.py`)

Ingest turns the sample stream into **activities**: maximal runs of identical consecutive samples.

```
for each file in sorted(data/raw/*.jsonl):
    read bytes from ingest_state[file].byte_offset to the last "\n"   # ignore a half-written line
    advance the offset past the complete lines
    for each sample:
        key = (app, bundle_id, title, url, idle)
        cur = most recent activity (by end_ts) in the DB
        if sample.ts < cur.start:                    skip   (out of order or already seen)
        if sample.ts − cur.end ≤ GAP_S (15 s):
            if key == cur.key:   cur.end = max(cur.end, ts + interval)   → extend
            elif ts < cur.end:   cur.end = ts                            → trim, no overlaps
        else: (gap) the previous activity stays closed at its last sample
        otherwise insert a new activity [ts, ts + interval)
```

- **Incremental and idempotent:** re-running reads nothing new, and the currently open activity keeps extending across runs.
- **Gaps** (sleep, lock, pause, quitting the app) close the activity, so the time between isn't counted.
- **Domain:** taken from the URL hostname with a leading `www.` stripped.
- **Timestamps** are stored as local naive ISO-8601 strings, at seconds precision.

### 4.3 Queries (`src/timetrack/queries.py`)

- `activities_df(conn, start, end, include_idle)` returns a pandas frame for activities whose `start_ts` falls in `[start, end+1d)`. It adds `category` (via `classify.category`, overridden to `idle` when the activity is idle), `start`, `end` and `day`.
- `totals_by(df, column)` and `category_totals(df)` are aggregations.
- `today_work_seconds(conn)` is the number shown in the menu bar.
- An activity that spans midnight is counted entirely in the day it started.

### 4.4 Status CLI (`src/status.py`, `make -s status`)

It ingests, then prints exactly:

```json
{"generated_at": "2026-10-02T17:32:36", "today_work_s": 2619.17}
```

Keys are sorted, snake_case, and there's nothing else on stdout; the Swift side decodes it with `CodingKeys`.

### 4.5 Menu bar app UI

- **Title:**
  - `⏱ <h>h<mm>` (or `<m>m`) for today's work time
  - `⏸ TT` when paused
  - `⚠︎ TT` without Accessibility
  - `⏱ TT` before the first status arrives
- **Panel** (borderless `NSPanel`, 300×200):
  - "WORKED TODAY" with the big number
  - state (Tracking / Paused / Screen locked / Asleep / No Accessibility)
  - Pause/Resume, Refresh, Quit, Dashboard
  - the last error, if any
- **Dashboard button:** probes `http://localhost:8600`. If it's down, it runs `make app` and opens the browser after 4 s.
- **Running `make`:** done through `/usr/bin/env make` with `PATH` extended by `/opt/homebrew/bin`, `/usr/local/bin` and `~/.local/bin`, so a GUI-launched app finds `uv`.

### 4.6 Dashboard (`src/app.py`)

There is a single page:
- period picker: Today / Yesterday / Last 7 days / This month / Custom
- metrics: Work · Entertainment · Idle
- stacked per-day bars (only when the range has more than one day)
- Gantt-style timeline for one day (y = app, colour = category)
- colours: work = blue, entertainment = orange, idle = neutral gray. The pair is colour-blind safe (OKLab ΔE ≈ 25 under protan/deutan/tritan simulation), with separate light and dark values picked from `st.context.theme.type`, and every chart has a legend so colour is never the only cue
- tables of apps and websites (time + share)
- drill-down per app: window titles and URLs

## 5. Data contracts

### 5.1 Raw sample (one JSON object per line)

| Key | Type | Notes |
|---|---|---|
| `ts` | float | Unix epoch seconds at sampling time |
| `app` | string | `localizedName`, e.g. `Google Chrome`, `Zed`, `iTerm2` |
| `bundle_id` | string? | e.g. `com.google.Chrome` |
| `title` | string? | Focused window title; absent without Accessibility or for private apps |
| `url` | string? | Chrome active-tab URL only |
| `idle` | bool | No input for ≥ `idleMinutes` |
| `interval` | float | Sampling period in seconds (default 5); used as the duration of a lone sample |

Missing optional keys are omitted, not null. Unknown keys are ignored by ingest.

### 5.2 SQLite (`data/timetrack.db`)

```sql
CREATE TABLE activities (
    id INTEGER PRIMARY KEY,
    start_ts TEXT NOT NULL,   -- local ISO, seconds
    end_ts   TEXT NOT NULL,
    duration_s REAL NOT NULL,
    app TEXT NOT NULL, bundle_id TEXT, title TEXT, url TEXT, domain TEXT,
    idle INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_activities_start ON activities(start_ts);

CREATE TABLE ingest_state (file TEXT PRIMARY KEY, byte_offset INTEGER NOT NULL DEFAULT 0);
```

**Migration policy:** `init_schema` runs on every connection. If it finds tables from an older schema, `drop_legacy_schema` drops everything, including `ingest_state`, so the next ingest rebuilds from raw. This is safe because the DB holds only derived data.

### 5.3 Files under `data/` (git-ignored)

| Path | Writer | Meaning |
|---|---|---|
| `raw/YYYY-MM-DD.jsonl` | Sampler | Source of truth |
| `timetrack.db` | Python | Derived cache |
| `paused` | Menu app | Exists while tracking is paused |

## 6. macOS permissions and signing

| Permission | Needed for | Granted via |
|---|---|---|
| Accessibility | Window titles | System Settings toggle; it can't be enabled from the CLI because of SIP. `AXIsProcessTrustedWithOptions` prompts on launch. |
| Automation → Chrome | Tab URL | macOS prompt on first AppleScript call (`NSAppleEventsUsageDescription` in `Info.plist`) |

**Signing.** TCC (the permission database) binds a grant to the app's designated requirement. An ad-hoc signature (`codesign -s -`) changes with every build, so after a rebuild the Settings toggle stays on but no longer applies. To avoid this:
- `setup-signing.sh` (`make menu-signing`) creates a self-signed **TimeTrack Dev** code-signing identity in the login keychain, using LibreSSL to generate the cert and `security import -T /usr/bin/codesign`.
- `build.sh` signs with it when it's present, falling back to ad-hoc otherwise.
- The resulting requirement is `identifier "<bundle id>" and certificate leaf = H"…"`, which is stable across builds.
- "CSSMERR_TP_NOT_TRUSTED" is expected and harmless for local use.

`make menu-reset-permissions` runs `tccutil reset` for Accessibility and AppleEvents on the bundle ID to clear stale grants.

## 7. Privacy and security

- **Nothing leaves the machine.** There are no network calls apart from the localhost dashboard probe.
- **Streamlit** is bound to `127.0.0.1` (`.streamlit/config.toml` and `make app`), so other devices on the network can't read titles or URLs. Its usage telemetry is disabled.
- **What's recorded:** app names, window titles (which can include email subjects, document names and chat names) and Chrome URLs. No keystrokes, screenshots or page content.
- **Private-app list** suppresses titles and URLs for sensitive apps. Pause stops sampling completely.
- **Git:** `.gitignore` excludes `data/`, `*.db`, `*.jsonl`, backups, key material (`*.p12`, `*.pem`, `*.key`) and `.env` / Streamlit secrets. The signing key exists only in the keychain.

## 8. Operations (Makefile)

| Target | Action |
|---|---|
| `app` / `stop` | Start Streamlit on `PORT` (8600, localhost) in the background / kill the process listening on `PORT` |
| `ingest` / `status` | Ingest raw samples / ingest + status JSON |
| `menu-build` / `menu-restart` / `menu-stop` | Build `.app` / build, quit and relaunch / quit |
| `menu-signing` / `menu-reset-permissions` | One-time identity / clear stale TCC grants |
| `test` | `uv run --with pytest pytest` |
| `reset-db` | Confirm, then delete the DB and re-ingest from raw |

Overridable variables: `PORT`, `BUNDLE_ID`.

## 9. Testing

`make test` runs pytest; tests use an in-memory SQLite fixture.
- **Ingest:** merging, app switch, gap split, idle split, domain extraction, incremental offsets with a partial trailing line.
- **Queries:** VLC and Stremio vs everything else, category totals including idle, per-app totals, status shape, dropping the legacy schema.
- **UI:** `streamlit.testing.v1.AppTest` runs `src/app.py` against an empty DB and against seeded raw files (with `db.DB_PATH` and `db.RAW_DIR` monkeypatched), and checks the metric values.
- **Swift:** not unit-tested. It's verified by building and checking that `data/raw` grows and `make -s status` returns valid JSON.

## 10. Decision log

| # | Decision | Reason |
|---|---|---|
| 1 | Swift for sampling, Python for logic, JSONL between them | Native API access where needed, with all rules in testable Python. Raw logs make the logic replayable. |
| 2 | No Docker | The sampler must see the macOS window server, so a container would add complexity for nothing. |
| 3 | Lazy ingestion instead of a daemon | One process fewer. The 60 s menu poll keeps the DB fresh enough. |
| 4 | Dashboard on 8600, localhost-only | Avoids clashing with other Streamlit apps on 8501 and stops LAN exposure of titles and URLs. |
| 5 | Chrome URL via AppleScript; Firefox by title only | Firefox has no AppleScript URL API. A WebExtension was rejected as too much setup. |
| 6 | Window titles via Accessibility | Titles carry the folder, document or page name, which makes the breakdown meaningful. |
| 7 | Self-signed identity instead of ad-hoc signing | Ad-hoc signatures silently invalidate permission grants on every rebuild. |
| 8 | **Projects, rules and a "working on" mode were built, then removed** | Version 1 had projects, regex/domain/title rules, a manual > focus > rule precedence chain, retroactive time-block assignment with activity splitting, and a five-page UI. That was too much to maintain for the actual need (daily work time), so it was replaced by a fixed two-app entertainment list. |
| 9 | Classification at query time | Changing the list needs no migration and applies to all history. |
| 10 | Idle = 5 min without input, excluded from work | "Stopped working" is inferred, with no manual clock-out. |

## 11. Known limitations and possible extensions

**Limitations**
- **URLs:** only Chrome. Firefox, Safari and other browsers are identified by window title.
- **Websites:** never entertainment, since only apps are classified.
- **Idle:** the first 5 min of inactivity are counted as work, and passive watching or reading becomes idle.
- **Time zones:** local naive timestamps, so a DST change or travel can skew one day.
- **Displays:** only the frontmost app counts, not what's visible on a second monitor.

**Natural extensions**, each small and self-contained:
1. An entertainment **domain** list in `classify.py` (e.g. `x.com`, `youtube.com`).
2. More Chromium browsers in `urlScripts` (Arc, Brave, Edge share Chrome's AppleScript dictionary).
3. A daily or weekly goal shown in the menu bar.
4. Retention, such as compressing or pruning raw files older than N months.
5. Projects again, if the need returns. The removed design (decision 8) is a tested starting point.
