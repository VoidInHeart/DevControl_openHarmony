from __future__ import annotations

import sqlite3
import threading
from pathlib import Path
from typing import Any


class GatewayStorage:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(path, check_same_thread=False)
        self._connection.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        self._initialize()

    def _initialize(self) -> None:
        with self._connection:
            self._connection.execute("PRAGMA journal_mode=WAL")
            self._connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS audit_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp_ms INTEGER NOT NULL,
                    client_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    action TEXT NOT NULL,
                    result TEXT NOT NULL,
                    error_code TEXT,
                    message_id_suffix TEXT NOT NULL,
                    details TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_audit_timestamp
                    ON audit_logs(timestamp_ms DESC);

                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp_ms INTEGER NOT NULL,
                    device_id TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    code TEXT NOT NULL,
                    description TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_alert_timestamp
                    ON alerts(timestamp_ms DESC);

                CREATE TABLE IF NOT EXISTS environment_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp_ms INTEGER NOT NULL,
                    device_id TEXT NOT NULL,
                    temperature_celsius REAL NOT NULL,
                    humidity_percent REAL NOT NULL,
                    illuminance_lux REAL NOT NULL,
                    presence INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_environment_device_time
                    ON environment_history(device_id, timestamp_ms DESC);
                """
            )

    def record_audit(
        self,
        *,
        timestamp_ms: int,
        client_id: str,
        device_id: str,
        action: str,
        result: str,
        error_code: str | None,
        message_id: str,
        details: str | None = None,
    ) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO audit_logs (
                    timestamp_ms, client_id, device_id, action, result,
                    error_code, message_id_suffix, details
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    timestamp_ms,
                    client_id,
                    device_id,
                    action,
                    result,
                    error_code,
                    message_id[-8:],
                    details,
                ),
            )

    def record_alert(
        self,
        *,
        timestamp_ms: int,
        device_id: str,
        severity: str,
        code: str,
        description: str,
    ) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO alerts (
                    timestamp_ms, device_id, severity, code, description
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (timestamp_ms, device_id, severity, code, description),
            )

    def record_environment(
        self,
        *,
        timestamp_ms: int,
        device_id: str,
        temperature_celsius: float,
        humidity_percent: float,
        illuminance_lux: float,
        presence: bool,
    ) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO environment_history (
                    timestamp_ms, device_id, temperature_celsius,
                    humidity_percent, illuminance_lux, presence
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    timestamp_ms,
                    device_id,
                    temperature_celsius,
                    humidity_percent,
                    illuminance_lux,
                    1 if presence else 0,
                ),
            )

    def get_logs(self, cursor: int | None, limit: int) -> dict[str, Any]:
        effective_limit = min(max(limit, 1), 100)
        params: list[object] = []
        where = ""
        if cursor is not None:
            where = "WHERE id < ?"
            params.append(cursor)
        params.append(effective_limit + 1)
        with self._lock:
            rows = self._connection.execute(
                f"""
                SELECT id, timestamp_ms, client_id, device_id, action,
                       result, error_code, message_id_suffix, details
                FROM audit_logs
                {where}
                ORDER BY id DESC
                LIMIT ?
                """,
                params,
            ).fetchall()
        has_more = len(rows) > effective_limit
        visible = rows[:effective_limit]
        items = [
            {
                "id": row["id"],
                "timestamp": row["timestamp_ms"],
                "clientId": row["client_id"],
                "deviceId": row["device_id"],
                "action": row["action"],
                "result": row["result"],
                "errorCode": row["error_code"],
                "messageIdSuffix": row["message_id_suffix"],
                "details": row["details"],
            }
            for row in visible
        ]
        return {
            "items": items,
            "nextCursor": visible[-1]["id"] if has_more and visible else None,
        }

    def get_alerts(self, limit: int) -> list[dict[str, object]]:
        effective_limit = min(max(limit, 1), 100)
        with self._lock:
            rows = self._connection.execute(
                """
                SELECT id, timestamp_ms, device_id, severity, code, description
                FROM alerts
                ORDER BY id DESC
                LIMIT ?
                """,
                (effective_limit,),
            ).fetchall()
        return [
            {
                "id": row["id"],
                "timestamp": row["timestamp_ms"],
                "deviceId": row["device_id"],
                "severity": row["severity"],
                "code": row["code"],
                "description": row["description"],
            }
            for row in rows
        ]

    def get_environment_history(
        self, device_id: str, from_ms: int, to_ms: int, limit: int
    ) -> list[dict[str, object]]:
        effective_limit = min(max(limit, 1), 50_000)
        with self._lock:
            rows = self._connection.execute(
                """
                SELECT timestamp_ms, temperature_celsius, humidity_percent,
                       illuminance_lux, presence
                FROM environment_history
                WHERE device_id = ? AND timestamp_ms BETWEEN ? AND ?
                ORDER BY timestamp_ms ASC
                LIMIT ?
                """,
                (device_id, from_ms, to_ms, effective_limit),
            ).fetchall()
        return [
            {
                "timestamp": row["timestamp_ms"],
                "temperatureCelsius": row["temperature_celsius"],
                "humidityPercent": row["humidity_percent"],
                "illuminanceLux": row["illuminance_lux"],
                "presence": bool(row["presence"]),
            }
            for row in rows
        ]

    def prune_environment_history(self, before_ms: int) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                "DELETE FROM environment_history WHERE timestamp_ms < ?",
                (before_ms,),
            )

    def table_columns(self, table: str) -> list[str]:
        with self._lock:
            rows = self._connection.execute(
                f"PRAGMA table_info({table})"
            ).fetchall()
        return [str(row["name"]) for row in rows]

    def close(self) -> None:
        with self._lock:
            self._connection.close()
