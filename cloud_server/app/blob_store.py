from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class LocalBlobStore:
    def __init__(self, root: str | None = None) -> None:
        base_root = Path(__file__).resolve().parent.parent / 'data' / 'object_store'
        self.root = Path(root) if root else base_root
        self.root.mkdir(parents=True, exist_ok=True)

    def put_json(self, object_key: str, payload: dict[str, Any]) -> str:
        path = self.root / object_key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8')
        return object_key

    def get_json(self, object_key: str) -> dict[str, Any]:
        path = self.root / object_key
        return json.loads(path.read_text(encoding='utf-8'))

    def exists(self, object_key: str) -> bool:
        return (self.root / object_key).exists()
