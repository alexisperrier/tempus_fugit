def format_duration(seconds: float | int | None) -> str:
    """Format seconds as '3h05', '42m' or '15s'."""
    seconds = int(round(seconds or 0))
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h{minutes:02d}"
    if minutes:
        return f"{minutes}m"
    return f"{secs}s"
