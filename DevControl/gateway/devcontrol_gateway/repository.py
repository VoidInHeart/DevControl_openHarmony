from __future__ import annotations

import json
import sqlite3
import threading
from pathlib import Path
from typing import Any


class GatewayRepository:
    def __init__(self, database_path: Path) -> None:
        database_path.parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(database_path, check_same_thread=False)
        self._connection.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        self._initialize()

    def _initialize(self) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                """
                CREATE TABLE IF NOT EXISTS gateway_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp_ms INTEGER NOT NULL,
                    category TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    client_id TEXT NOT NULL,
                    action TEXT NOT NULL,
                    result TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    detail_json TEXT NOT NULL
                )
                """
            )
            self._connection.execute(
                "CREATE INDEX IF NOT EXISTS gateway_log_time ON gateway_log(timestamp_ms DESC)"
            )

    def append_log(
        self,
        *,
        timestamp_ms: int,
        category: str,
        device_id: str,
        client_id: str,
        action: str,
        result: str,
        reason: str = "",
        detail: dict[str, Any] | None = None,
    ) -> None:
        safe_detail = detail or {}
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO gateway_log (
                    timestamp_ms, category, device_id, client_id, action, result, reason, detail_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    timestamp_ms,
                    category,
                    device_id,
                    client_id,
                    action,
                    result,
                    reason,
                    json.dumps(safe_detail, ensure_ascii=False, separators=(",", ":")),
                ),
            )

    def list_logs(self, limit: int = 100, offset: int = 0) -> list[dict[str, Any]]:
        safe_limit = min(max(limit, 1), 200)
        safe_offset = max(offset, 0)
        with self._lock:
            rows = self._connection.execute(
                """
                SELECT timestamp_ms, category, device_id, client_id, action, result, reason, detail_json
                FROM gateway_log ORDER BY timestamp_ms DESC LIMIT ? OFFSET ?
                """,
                (safe_limit, safe_offset),
            ).fetchall()
        return [
            {
                "timestamp": row["timestamp_ms"],
                "category": row["category"],
                "deviceId": row["device_id"],
                "clientId": row["client_id"],
                "action": row["action"],
                "result": row["result"],
                "reason": row["reason"],
                "detail": json.loads(row["detail_json"]),
            }
            for row in rows
        ]

    def close(self) -> None:
        with self._lock:
            self._connection.close()
