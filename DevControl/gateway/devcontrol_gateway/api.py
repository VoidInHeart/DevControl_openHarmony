from __future__ import annotations

import asyncio
import json
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, Header, HTTPException, Query, Request, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from .config import GatewayConfig
from .models import ClientSession
from .repository import GatewayRepository
from .security import CredentialStore, PairingError
from .service import GatewayService


class PairRequest(BaseModel):
    pairingCode: str = Field(min_length=6, max_length=6)
    clientId: str = Field(min_length=3, max_length=128)


class ConnectionHub:
    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()
        self._lock = asyncio.Lock()

    async def add(self, socket: WebSocket) -> None:
        async with self._lock:
            self._connections.add(socket)

    async def remove(self, socket: WebSocket) -> None:
        async with self._lock:
            self._connections.discard(socket)

    async def broadcast(self, message: dict[str, object]) -> None:
        payload = json.dumps(message, ensure_ascii=False, separators=(",", ":"))
        async with self._lock:
            sockets = list(self._connections)
        stale: list[WebSocket] = []
        for socket in sockets:
            try:
                await socket.send_text(payload)
            except RuntimeError:
                stale.append(socket)
        if stale:
            async with self._lock:
                for socket in stale:
                    self._connections.discard(socket)


def create_app(config: GatewayConfig | None = None) -> FastAPI:
    active_config = config or GatewayConfig.from_environment()
    repository = GatewayRepository(active_config.database_path)
    credentials = CredentialStore(
        active_config.pairing_ttl_seconds, active_config.credential_ttl_seconds
    )
    service = GatewayService(repository)
    hub = ConnectionHub()

    async def simulation_loop() -> None:
        heartbeat_tick = 0
        while True:
            await asyncio.sleep(2)
            changed = service.tick()
            for device in changed:
                await hub.broadcast(service.state_event(device))
            heartbeat_tick += 1
            if heartbeat_tick >= 7:
                heartbeat_tick = 0
                await hub.broadcast(service.heartbeat_event())

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        task = asyncio.create_task(simulation_loop())
        print(
            f"DevControl pairing code: {credentials.pairing_code} "
            f"(valid until {credentials.pairing_expires_at})"
        )
        try:
            yield
        finally:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
            repository.close()

    app = FastAPI(title="DevControl Virtual Gateway", version="1.0.0", lifespan=lifespan)

    def session_from_header(authorization: str | None) -> ClientSession:
        credential = _bearer_token(authorization)
        session = credentials.authenticate(credential)
        if session is None:
            raise HTTPException(status_code=401, detail="AUTH_FAILED")
        return session

    @app.get("/api/v1/health")
    async def health() -> dict[str, object]:
        return {
            "status": "ok",
            "protocolVersion": "1.0",
            "serviceVersion": "1.0.0",
            "timestamp": GatewayService._now_ms(),
        }

    @app.post("/api/v1/pair")
    async def pair(payload: PairRequest, request: Request) -> dict[str, object]:
        source = request.client.host if request.client else "unknown"
        try:
            session, credential, data_key = credentials.pair(
                source, payload.pairingCode, payload.clientId
            )
        except PairingError as error:
            code = str(error)
            status = 429 if code == "RATE_LIMITED" else 401
            raise HTTPException(status_code=status, detail=code) from error
        return {
            "clientId": session.client_id,
            "credential": credential,
            "dataKey": data_key,
            "expiresAt": session.expires_at,
        }

    @app.get("/api/v1/devices")
    async def devices(authorization: str | None = Header(default=None)) -> dict[str, object]:
        session_from_header(authorization)
        return {"devices": service.snapshot(), "timestamp": GatewayService._now_ms()}

    @app.get("/api/v1/logs")
    async def logs(
        authorization: str | None = Header(default=None),
        limit: int = Query(default=100, ge=1, le=200),
        offset: int = Query(default=0, ge=0),
    ) -> dict[str, object]:
        session_from_header(authorization)
        items = repository.list_logs(limit, offset)
        return {"items": items, "limit": limit, "offset": offset}

    @app.websocket("/ws/v1/events")
    async def events(socket: WebSocket) -> None:
        credential = _bearer_token(socket.headers.get("authorization"))
        session = credentials.authenticate(credential)
        if session is None:
            await socket.close(code=4401, reason="AUTH_FAILED")
            return
        await socket.accept()
        await hub.add(socket)
        await socket.send_json(service.snapshot_event(service.snapshot()))
        try:
            while True:
                message = await socket.receive_json()
                if not isinstance(message, dict):
                    await socket.send_json(
                        {
                            "protocolVersion": "1.0",
                            "messageId": GatewayService._event_id(),
                            "deviceId": "gateway",
                            "timestamp": GatewayService._now_ms(),
                            "type": "command.result",
                            "action": "",
                            "success": False,
                            "errorCode": "INVALID_COMMAND",
                            "errorMessage": "message must be an object",
                        }
                    )
                    continue
                outcome = service.process_command(message, session)
                await socket.send_json(outcome.result)
                for device in outcome.changed_devices:
                    await hub.broadcast(service.state_event(device))
                for alert in outcome.alerts:
                    await hub.broadcast(alert)
        except WebSocketDisconnect:
            pass
        finally:
            await hub.remove(socket)

    app.state.gateway_config = active_config
    app.state.credentials = credentials
    app.state.service = service
    return app


def _bearer_token(authorization: str | None) -> str:
    if not authorization:
        return ""
    scheme, separator, token = authorization.partition(" ")
    if separator and scheme.lower() == "bearer":
        return token.strip()
    return ""
