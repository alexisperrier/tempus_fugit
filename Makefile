.PHONY: help app stop ingest status menu-build menu-restart menu-stop menu-signing menu-reset-permissions test reset-db

.DEFAULT_GOAL := help

PORT ?= 8600
BUNDLE_ID ?= com.alexis.timetrack.menu

help:
	@echo "Available commands:"
	@echo "  make app          Start the Streamlit app (background, http://localhost:$(PORT))"
	@echo "  make stop         Stop the running Streamlit app"
	@echo "  make ingest       Merge new sampler data (data/raw/*.jsonl) into SQLite"
	@echo "  make status       Ingest, then print today's working time as JSON (used by the menu app)"
	@echo "  make menu-build   Build the macOS menu bar app"
	@echo "  make menu-restart Rebuild and relaunch the macOS menu bar app"
	@echo "  make menu-stop    Quit the menu bar app (stops tracking)"
	@echo "  make menu-signing One-time: create the 'TimeTrack Dev' signing identity (keeps permissions across rebuilds)"
	@echo "  make menu-reset-permissions  Clear stale Accessibility/Automation grants for the menu app"
	@echo "  make test         Run automated tests"
	@echo "  make reset-db     Delete data/timetrack.db and re-ingest from raw samples"

app:
	uv run streamlit run src/app.py --server.address 127.0.0.1 --server.port $(PORT) &

stop:
	-lsof -ti tcp:$(PORT) -sTCP:LISTEN | xargs kill 2>/dev/null

ingest:
	uv run python src/ingest.py

status:
	uv run python src/status.py

menu-build:
	cd macos/TimeTrackMenu && BUNDLE_ID=$(BUNDLE_ID) bash ./build.sh

menu-restart: menu-build
	-pkill -x TimeTrackMenu
	sleep 0.2
	open macos/TimeTrackMenu/TimeTrackMenu.app

menu-stop:
	-pkill -x TimeTrackMenu

menu-signing:
	bash macos/TimeTrackMenu/setup-signing.sh

menu-reset-permissions:
	tccutil reset Accessibility $(BUNDLE_ID)
	tccutil reset AppleEvents $(BUNDLE_ID)

test:
	uv run --with pytest pytest

reset-db:
	@read -p "Delete data/timetrack.db and rebuild it from data/raw? [y/N] " ans; \
	if [ "$$ans" = "y" ]; then rm -f data/timetrack.db && uv run python src/ingest.py; else echo "Aborted."; fi
