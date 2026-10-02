"""Print today's working time as JSON for the menu bar app (`make -s status`)."""
import json
from datetime import datetime

from timetrack.db import connect
from timetrack.ingest import ingest_raw_dir
from timetrack.queries import today_work_seconds
from timetrack.schema import init_schema


def build_status(conn) -> dict:
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "today_work_s": today_work_seconds(conn),
    }


def main() -> None:
    conn = connect()
    init_schema(conn)
    ingest_raw_dir(conn)
    print(json.dumps(build_status(conn), sort_keys=True))
    conn.close()


if __name__ == "__main__":
    main()
