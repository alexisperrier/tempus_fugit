# Set up TimeTrack on your Mac

TimeTrack is a small personal time tracker for macOS. All of its data stays on your Mac.

- A **menu bar app** records which app is in front every 5 seconds, plus the window title and, in Google Chrome, the tab URL. The menu bar shows how long you've worked today, e.g. `⏱ 3h12`.
- A **web dashboard** (Streamlit, at http://localhost:8600) shows time per app, per website and per day, with a timeline.
- **Work vs entertainment:** VLC and Stremio count as entertainment and everything else counts as work. If there's no keyboard or mouse input for 5 minutes, you've stopped working, and that idle time is never counted as work.

Setup takes about 10 minutes.

---

## 1. Requirements

| What | Check | Install |
|---|---|---|
| macOS 15 (Sequoia) or later | ` → About This Mac` | — |
| Xcode Command Line Tools (provides `swiftc`, `make`, `git`) | `swiftc --version` | `xcode-select --install` |
| uv (Python package manager; it installs Python 3.11 itself) | `uv --version` | `curl -LsSf https://astral.sh/uv/install.sh \| sh`, then open a new terminal |

You don't need the full Xcode app, Docker, or a system Python.

## 2. Get the code

Put the project folder anywhere you like, for example `~/work/time_tracking`, using either:

- `git clone <repo-url> ~/work/time_tracking`, or
- a copy of the folder from the owner. They should create it with `git archive --format=zip -o timetrack.zip HEAD`, which leaves out their `data/` and `.venv/`.

The menu app remembers the folder it was built from. If you move the folder later, run `make menu-restart` to rebuild it.

```bash
cd ~/work/time_tracking
```

## 3. Install and test the Python side

```bash
uv sync      # creates .venv with Streamlit, pandas, altair
make test    # should end with "14 passed" (or more)
```

## 4. Create a signing identity (one-time, important)

macOS ties the Accessibility permission to the app's code signature. Without a stable signature, every rebuild makes the app look new to macOS: the old permission toggle stays on but stops working, and the menu shows "No Accessibility".

The following command creates a self-signed certificate named **TimeTrack Dev** in your login keychain. All builds are then signed with it.

```bash
make menu-signing
```

- It prints `"TimeTrack Dev" (CSSMERR_TP_NOT_TRUSTED)`. That's expected for a self-signed certificate and doesn't affect local signing.
- If macOS asks whether `codesign` may use the key, choose **Always Allow**.

**Optional, to avoid clashing with the original owner's identifiers:** set your own bundle ID by adding `BUNDLE_ID=com.<yourname>.timetrack.menu` to every `make menu-*` command. Alternatively, change the default once at the top of the `Makefile`.

## 5. Build and launch the menu bar app

```bash
make menu-restart
```

- **Expected:** a `⏱ 0m`, `⚠︎ TT` or similar item appears in the menu bar. `make: [menu-restart] Error 1 (ignored)` on the first run only means there was no previous copy to quit.
- **Check the build signed with the stable identity:** the output must say `Signing with 'TimeTrack Dev'`. If it says `ad-hoc`, go back to step 4.

## 6. Grant permissions (one-time)

1. **Accessibility** (needed for window titles)
   - Open System Settings → Privacy & Security → **Accessibility** and turn on **TimeTrackMenu**.
   - If it isn't listed, click **+** and pick `macos/TimeTrackMenu/TimeTrackMenu.app` from the project folder.
   - Turning this permission on can't be done from the command line; macOS blocks it.
2. **Automation → Google Chrome** (needed for tab URLs)
   - The first time Chrome is the front app, macOS asks whether TimeTrackMenu may control Chrome. Click **OK**.
   - To change it later: System Settings → Privacy & Security → Automation.
3. **Firefox:** Firefox has no scripting interface for URLs, so Firefox is tracked by window title only. Safari and other browsers are also tracked by title only.

Click the menu bar item. The panel should show **Tracking** in green.

## 7. Check that data is being recorded

```bash
tail -3 data/raw/$(date +%F).jsonl   # a new line every 5 s, with "title" (and "url" in Chrome)
make -s status                       # {"generated_at": "...", "today_work_s": 123.4}
```

## 8. Open the dashboard

```bash
make app     # starts Streamlit in the background on http://localhost:8600
```

Alternatively, click **Dashboard** in the menu bar panel; it starts Streamlit for you if needed. `make stop` stops it. Port 8600 is used so it doesn't clash with other Streamlit apps on the default port 8501. The dashboard only listens on this Mac (127.0.0.1), so nobody else on your network can open it, and Streamlit's usage telemetry is turned off (`.streamlit/config.toml`). To pick another port, run `make app PORT=8700`.

## 9. Start tracking automatically at login (optional)

Run this from the project folder:

```bash
osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$(pwd)/macos/TimeTrackMenu/TimeTrackMenu.app\", hidden:true}"
```

You can also do it by hand: System Settings → General → Login Items → **+** → `TimeTrackMenu.app`.

---

## Everyday use

| You want to… | Do |
|---|---|
| See today's work time | Look at the menu bar (`⏱ 3h12`) |
| Pause tracking (private time) | Menu bar → **Pause**; **Resume** to restart |
| Explore apps, sites and the timeline | Menu bar → **Dashboard**, or `make app` |
| Stop tracking completely | Menu bar → power button, or `make menu-stop` |

Screen lock and sleep pause tracking automatically.

## Customizing

- **Entertainment apps:** edit `ENTERTAINMENT_APPS` in `src/timetrack/classify.py` (lowercase app names as shown in the dashboard). This applies to past data too, with no re-processing needed.
- **Idle threshold** (default 5 min):
  ```bash
  defaults write com.alexis.timetrack.menu idleMinutes -int 10
  make menu-restart
  ```
  Use your own bundle ID here if you changed it in step 4.
- **Private apps** (recorded without window titles; default `1Password, Keychain Access`):
  ```bash
  defaults write com.alexis.timetrack.menu privateApps "1Password, Signal"
  ```

## Where the data lives

- `data/raw/YYYY-MM-DD.jsonl`: raw samples, one line every 5 s. These are the source of truth.
- `data/timetrack.db`: SQLite database built from the raw files. It is safe to delete; `make reset-db` rebuilds it.
- `data/` is git-ignored. Nothing is sent anywhere.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Menu shows **No Accessibility** / `⚠︎ TT` although the toggle is on | The grant belongs to an older build. Run `make menu-signing` (if you skipped step 4), then `make menu-reset-permissions` and `make menu-restart`, and turn the toggle on again. |
| Build says `ad-hoc signing` | The `TimeTrack Dev` identity is missing: run `make menu-signing`. |
| Menu shows an error like `uv: command not found` | The menu app looks for `uv` in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`. Install uv in one of these. |
| No `url` in samples while using Chrome | System Settings → Privacy & Security → Automation → TimeTrackMenu → enable Google Chrome. |
| Dashboard doesn't open | Check whether something else uses port 8600 (`lsof -i :8600`), or use `make app PORT=8700`. The menu's Dashboard button always opens 8600. |
| Totals look wrong after editing code | `make reset-db` rebuilds everything from `data/raw`. |

## Uninstall

```bash
make menu-stop
make stop
make menu-reset-permissions
defaults delete com.alexis.timetrack.menu
security delete-certificate -c "TimeTrack Dev"   # removes the signing identity
rm -rf ~/work/time_tracking                     # the project folder, including your data
```

Also remove the login item if you added one.

---

## How it fits together (for the curious)

```
TimeTrackMenu (Swift, menu bar)  ──every 5 s──▶  data/raw/YYYY-MM-DD.jsonl
        │  every 60 s runs `make -s status`              │
        ▼                                               ▼
  "⏱ 3h12" in the menu bar          src/timetrack/ingest.py ──▶ data/timetrack.db
                                                        ▲
                         Streamlit dashboard (src/app.py) ┘  (ingests on each load)
```

- **Stack:** uv + Python 3.11, plain `sqlite3`, Streamlit + Altair, a Makefile, and a native SwiftUI/AppKit menu bar app compiled directly with `swiftc` (`macos/TimeTrackMenu/build.sh`, no Xcode project).
- **How the sampler reads the screen:**
  - front app: `NSWorkspace`
  - window title: the Accessibility API
  - Chrome URL: AppleScript
  - idle detection: `CGEventSource` seconds since the last input
- **Merging:** ingest joins identical consecutive samples into activities. A gap over 15 s (sleep, lock, pause) ends an activity.
