from __future__ import annotations

import asyncio
import json
import time
from collections.abc import Awaitable, Callable
from typing import Any

from .config import GatewayConfig
from .devices import DeviceRegistry
from .errors import (
    INTERNAL_ERROR,
    REPLAY_DETECTED,
    GatewayError,
)
from .models import PROTOCOL_VERSION, SecureCommandEnvelope
from .security import ClientSession, SessionRegistry, decrypt_payload, now_ms
from .storage import GatewayStorage


EventSink = Callable[[dict[str, Any]], Awaitable[None]]


class GatewayService:
    IDEMPOTENCY_WINDOW_SECONDS = 300
    TIMESTAMP_WINDOW_MS = 30_000

    def __init__(self, config: GatewayConfig) -> None:
        self.config = config
        self.storage = GatewayStorage(config.database)
        self.sessions = SessionRegistry(
            config.initial_pairing_code,
            credential_ttl_seconds=config.credential_ttl_seconds,
        )
        self.devices = DeviceRegistry(self.storage)
        self._result_cache: dict[
            tuple[str, str], tuple[float, dict[str, Any]]
        ] = {}
        self._nonce_cache: dict[tuple[str, str], float] = {}
        self._sinks: set[EventSink] = set()
        self._tasks: list[asyncio.Task[None]] = []
        self._command_lock = asyncio.Lock()
        self._closed = False

    async def start(self) -> None:
        if self.config.enable_background_tasks and not self._tasks:
            self._tasks = [
                asyncio.create_task(self._telemetry_loop()),
                asyncio.create_task(self._heartbeat_loop()),
            ]

    async def stop(self) -> None:
        for task in self._tasks:
            task.cancel()
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)
        self._tasks = []
        if not self._closed:
            self.storage.close()
            self._closed = True

    def add_sink(self, sink: EventSink) -> None:
        self._sinks.add(sink)

    def remove_sink(self, sink: EventSink) -> None:
        self._sinks.discard(sink)

    async def broadcast(self, event: dict[str, Any]) -> None:
        failed: list[EventSink] = []
        for sink in tuple(self._sinks):
            try:
                await sink(event)
            except Exception:
                failed.append(sink)
        for sink in failed:
            self._sinks.discard(sink)

    async def _telemetry_loop(self) -> None:
        try:
            while True:
                await asyncio.sleep(self.config.telemetry_interval_seconds)
                changed = await asyncio.to_thread(self.devices.tick)
                for device in changed:
                    await self.broadcast(self.state_event(device))
                cutoff = now_ms() - 7 * 24 * 60 * 60 * 1000
                await asyncio.to_thread(
                    self.storage.prune_environment_history, cutoff
                )
        except asyncio.CancelledError:
            return

    async def _heartbeat_loop(self) -> None:
        try:
            while True:
                await asyncio.sleep(15)
                await self.broadcast(
                    {
                        "protocolVersion": PROTOCOL_VERSION,
                        "type": "heartbeat",
                        "timestamp": now_ms(),
                    }
                )
        except asyncio.CancelledError:
            return

    @staticmethod
    def state_event(device: dict[str, Any]) -> dict[str, Any]:
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "type": "state.changed",
            "timestamp": now_ms(),
            "deviceId": device["id"],
            "stateVersion": device["stateVersion"],
            "device": device,
        }

    def _prune_security_windows(self) -> None:
        cutoff = time.monotonic() - self.IDEMPOTENCY_WINDOW_SECONDS
        self._result_cache = {
            key: value
            for key, value in self._result_cache.items()
            if value[0] >= cutoff
        }
        self._nonce_cache = {
            key: timestamp
            for key, timestamp in self._nonce_cache.items()
            if timestamp >= cutoff
        }

    async def process_command(
        self, session: ClientSession, envelope: SecureCommandEnvelope
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        async with self._command_lock:
            self._prune_security_windows()
            cache_key = (session.credential_digest, envelope.messageId)
            cached = self._result_cache.get(cache_key)
            if cached is not None:
                return cached[1], []

            if abs(now_ms() - envelope.timestamp) > self.TIMESTAMP_WINDOW_MS:
                result = self._error_result(
                    envelope,
                    GatewayError(
                        REPLAY_DETECTED,
                        "命令时间戳超出允许的30秒窗口",
                    ),
                )
                self._cache_result(cache_key, result)
                self._audit(session, envelope, result)
                return result, []

            nonce_key = (session.credential_digest, envelope.nonce)
            if nonce_key in self._nonce_cache:
                result = self._error_result(
                    envelope,
                    GatewayError(REPLAY_DETECTED, "检测到重复 nonce"),
                )
                self._cache_result(cache_key, result)
                self._audit(session, envelope, result)
                return result, []
            self._nonce_cache[nonce_key] = time.monotonic()

            try:
                payload = decrypt_payload(session.data_key, envelope)
                device, details = await asyncio.to_thread(
                    self.devices.execute,
                    envelope.deviceId,
                    envelope.action,
                    payload,
                    envelope.expectedStateVersion,
                )
                result: dict[str, Any] = {
                    "protocolVersion": PROTOCOL_VERSION,
                    "type": "command.result",
                    "timestamp": now_ms(),
                    "messageId": envelope.messageId,
                    "deviceId": envelope.deviceId,
                    "action": envelope.action,
                    "success": True,
                    "error": None,
                    "details": details,
                }
                events: list[dict[str, Any]] = []
                if device is not None:
                    result["stateVersion"] = device["stateVersion"]
                    events.append(self.state_event(device))
                elif details is not None:
                    for item in details:
                        if item["success"]:
                            changed = self.devices.get(str(item["deviceId"]))
                            events.append(
                                self.state_event(
                                    self.devices.public_device(changed)
                                )
                            )
            except GatewayError as exc:
                result = self._error_result(envelope, exc)
                events = []
            except Exception:
                result = self._error_result(
                    envelope,
                    GatewayError(INTERNAL_ERROR, "网关内部处理失败"),
                )
                events = []

            events.extend(self.devices.drain_alerts())
            self._cache_result(cache_key, result)
            self._audit(session, envelope, result)
            return result, events

    def _cache_result(
        self, key: tuple[str, str], result: dict[str, Any]
    ) -> None:
        self._result_cache[key] = (time.monotonic(), result)

    @staticmethod
    def _error_result(
        envelope: SecureCommandEnvelope, error: GatewayError
    ) -> dict[str, Any]:
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "type": "command.result",
            "timestamp": now_ms(),
            "messageId": envelope.messageId,
            "deviceId": envelope.deviceId,
            "action": envelope.action,
            "success": False,
            "error": {
                "code": error.code,
                "message": error.message,
                "retryAfterSeconds": error.retry_after_seconds,
            },
            "details": None,
        }

    def _audit(
        self,
        session: ClientSession,
        envelope: SecureCommandEnvelope,
        result: dict[str, Any],
    ) -> None:
        error = result.get("error")
        error_code = error.get("code") if isinstance(error, dict) else None
        details = result.get("details")
        self.storage.record_audit(
            timestamp_ms=now_ms(),
            client_id=session.client_id,
            device_id=envelope.deviceId,
            action=envelope.action,
            result="success" if result["success"] else "failed",
            error_code=error_code,
            message_id=envelope.messageId,
            details=(
                json.dumps(details, ensure_ascii=False, separators=(",", ":"))
                if details is not None
                else None
            ),
        )
