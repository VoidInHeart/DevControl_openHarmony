from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from typing import Annotated, Any

from fastapi import (
    Depends,
    FastAPI,
    Header,
    Query,
    Request,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from .config import GatewayConfig
from .errors import AUTH_FAILED, GatewayError
from .models import (
    EnvironmentInjection,
    FaultRequest,
    PairRequest,
    PROTOCOL_VERSION,
    SecureCommandEnvelope,
)
from .security import ClientSession, now_ms
from .service import GatewayService


def _extract_bearer(authorization: str | None) -> str:
    if authorization is None or not authorization.startswith("Bearer "):
        raise GatewayError(AUTH_FAILED, "缺少客户端 Bearer 凭据", 401)
    credential = authorization[7:].strip()
    if not credential:
        raise GatewayError(AUTH_FAILED, "客户端凭据为空", 401)
    return credential


def create_app(
    config: GatewayConfig | None = None,
    service: GatewayService | None = None,
) -> FastAPI:
    effective_config = config or GatewayConfig.from_env()
    gateway = service or GatewayService(effective_config)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        await gateway.start()
        yield
        await gateway.stop()

    app = FastAPI(
        title="DevControl Gateway",
        version="1.1.0",
        lifespan=lifespan,
    )
    app.state.gateway = gateway

    @app.exception_handler(GatewayError)
    async def gateway_error_handler(
        _: Request, exc: GatewayError
    ) -> JSONResponse:
        headers = {}
        if exc.retry_after_seconds is not None:
            headers["Retry-After"] = str(exc.retry_after_seconds)
        return JSONResponse(
            status_code=exc.status_code,
            content=exc.to_dict(),
            headers=headers,
        )

    def require_session(
        authorization: Annotated[str | None, Header()] = None,
    ) -> ClientSession:
        credential = _extract_bearer(authorization)
        return gateway.sessions.authenticate(credential)

    @app.get("/")
    async def root() -> dict[str, object]:
        return {
            "name": "DevControl Gateway",
            "protocolVersion": PROTOCOL_VERSION,
        }

    @app.get("/api/v1/health")
    async def health() -> dict[str, object]:
        return {
            "status": "ok",
            "protocolVersion": PROTOCOL_VERSION,
            "gatewayVersion": "1.1.0",
            "serverTime": now_ms(),
        }

    @app.post("/api/v1/pair")
    async def pair(request: Request, body: PairRequest) -> dict[str, object]:
        source = request.client.host if request.client is not None else "unknown"
        response = gateway.sessions.pair(
            source, body.clientId, body.pairingCode
        )
        return response.model_dump()

    @app.get("/api/v1/devices")
    async def devices(
        session: ClientSession = Depends(require_session),
    ) -> dict[str, object]:
        del session
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "serverTime": now_ms(),
            "devices": gateway.devices.snapshot(),
        }

    @app.get("/api/v1/logs")
    async def logs(
        session: ClientSession = Depends(require_session),
        cursor: int | None = None,
        limit: int = Query(default=50, ge=1, le=100),
    ) -> dict[str, object]:
        del session
        page = gateway.storage.get_logs(cursor, limit)
        return {
            "protocolVersion": PROTOCOL_VERSION,
            **page,
            "alerts": gateway.storage.get_alerts(limit),
        }

    @app.get("/api/v1/history/environment")
    async def environment_history(
        session: ClientSession = Depends(require_session),
        deviceId: str = "env-living-01",
        fromTimestamp: int = Query(alias="from"),
        to: int | None = None,
        limit: int = Query(default=43_200, ge=1, le=50_000),
    ) -> dict[str, object]:
        del session
        items = gateway.storage.get_environment_history(
            deviceId, fromTimestamp, to or now_ms(), limit
        )
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "deviceId": deviceId,
            "items": items,
        }

    @app.websocket("/ws/v1/events")
    async def events(websocket: WebSocket) -> None:
        try:
            credential = _extract_bearer(
                websocket.headers.get("authorization")
            )
            session = gateway.sessions.authenticate(credential)
        except GatewayError:
            await websocket.close(code=4401, reason="AUTH_FAILED")
            return

        await websocket.accept()

        async def sink(event: dict[str, Any]) -> None:
            await websocket.send_json(event)

        gateway.add_sink(sink)
        await websocket.send_json(
            {
                "protocolVersion": PROTOCOL_VERSION,
                "type": "heartbeat",
                "timestamp": now_ms(),
            }
        )
        try:
            while True:
                try:
                    session = gateway.sessions.authenticate(credential)
                    raw = await asyncio.wait_for(
                        websocket.receive_json(),
                        timeout=gateway.sessions.remaining_seconds(session),
                    )
                except TimeoutError:
                    await websocket.close(code=4401, reason="AUTH_FAILED")
                    return
                except GatewayError:
                    await websocket.close(code=4401, reason="AUTH_FAILED")
                    return
                try:
                    session = gateway.sessions.authenticate(credential)
                    envelope = SecureCommandEnvelope.model_validate(raw)
                    result, state_events = await gateway.process_command(
                        session, envelope
                    )
                    await websocket.send_json(result)
                    for event in state_events:
                        await gateway.broadcast(event)
                except ValidationError:
                    await websocket.send_json(
                        {
                            "protocolVersion": PROTOCOL_VERSION,
                            "type": "command.result",
                            "timestamp": now_ms(),
                            "messageId": (
                                raw.get("messageId", "")
                                if isinstance(raw, dict)
                                else ""
                            ),
                            "success": False,
                            "error": {
                                "code": "INVALID_COMMAND",
                                "message": "命令信封格式无效",
                            },
                        }
                    )
                except GatewayError as exc:
                    if exc.code == AUTH_FAILED:
                        await websocket.close(code=4401, reason="AUTH_FAILED")
                        return
                    raise
        except WebSocketDisconnect:
            pass
        finally:
            gateway.remove_sink(sink)

    return app


def create_admin_app(
    service: GatewayService, admin_token: str
) -> FastAPI:
    app = FastAPI(
        title="DevControl Local Maintenance",
        version="1.1.0",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )

    def require_admin(
        x_admin_token: Annotated[str | None, Header()] = None,
    ) -> None:
        if x_admin_token != admin_token:
            raise GatewayError(AUTH_FAILED, "维护令牌无效", 401)

    @app.exception_handler(GatewayError)
    async def gateway_error_handler(
        _: Request, exc: GatewayError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=exc.to_dict(),
        )

    @app.get("/admin/v1/pairing-code")
    async def pairing_code(
        authorized: None = Depends(require_admin),
    ) -> dict[str, object]:
        del authorized
        return {
            "pairingCode": service.sessions.pairing_code,
            "expiresInSeconds": service.sessions.pairing_expires_in,
        }

    @app.post("/admin/v1/devices/{device_id}/fault")
    async def fault(
        device_id: str,
        body: FaultRequest,
        authorized: None = Depends(require_admin),
    ) -> dict[str, object]:
        del authorized
        device = service.devices.inject_fault(
            device_id, body.model_dump()
        )
        await service.broadcast(service.state_event(device))
        for alert in service.devices.drain_alerts():
            await service.broadcast(alert)
        return {"device": device}

    @app.post("/admin/v1/environment/inject")
    async def environment(
        body: EnvironmentInjection,
        authorized: None = Depends(require_admin),
    ) -> dict[str, object]:
        del authorized
        device = service.devices.inject_environment(body.model_dump())
        await service.broadcast(service.state_event(device))
        return {"device": device}

    return app
