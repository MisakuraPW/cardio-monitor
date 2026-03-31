from __future__ import annotations

from .config import settings
from .mqtt_ingest import run_forever
from .storage import SQLiteStorage


def main() -> None:  # pragma: no cover
    run_forever(
        storage=SQLiteStorage(),
        host=settings.mqtt_broker_host,
        port=settings.mqtt_broker_port,
        topic_prefix=settings.mqtt_topic_prefix,
        username=settings.mqtt_username,
        password=settings.mqtt_password,
    )


if __name__ == '__main__':  # pragma: no cover
    main()
