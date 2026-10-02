"""Work vs entertainment: a short list of entertainment apps, everything else is work."""

ENTERTAINMENT_APPS = {"vlc", "stremio"}


def category(app: str | None) -> str:
    return "entertainment" if (app or "").strip().lower() in ENTERTAINMENT_APPS else "work"
