# TimeTrackMenu

Native menu bar app: samples the frontmost app, window title (Accessibility) and Chrome URL (AppleScript) every few seconds into `<repo>/data/raw/`. It shows today's totals from `make -s status`.

Build and launch: `make menu-restart` from the repo root (or `./run.sh`). See the root README for permissions and for the `TimeTrack Dev` signing identity.

The repo path is baked into `Info.plist` (`TimeTrackRepoPath`) at build time, so rebuild after moving the checkout. Idle minutes and private apps live in UserDefaults.
