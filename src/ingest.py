import json

from timetrack.db import connect
from timetrack.ingest import ingest_raw_dir
from timetrack.schema import init_schema


def main() -> None:
    conn = connect()
    init_schema(conn)
    print(json.dumps(ingest_raw_dir(conn)))
    conn.close()


if __name__ == "__main__":
    main()
