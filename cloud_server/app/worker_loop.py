from __future__ import annotations

import time

from .analysis_service import process_pending_jobs
from .config import settings
from .storage import SQLiteStorage


def main() -> None:  # pragma: no cover
    storage = SQLiteStorage()
    while True:
        processed = process_pending_jobs(storage, settings, limit=10)
        if processed == 0:
            time.sleep(2)


if __name__ == '__main__':  # pragma: no cover
    main()
