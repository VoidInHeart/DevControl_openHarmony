from __future__ import annotations

import asyncio
import json
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator, Awaitable, Callable
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
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from pydantic import ValidationError
from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from .config import GatewayConfig
from .errors import AUTH_FAILED, GatewayError
from .models import (
    DeviceProvisionRequest,
    DeviceRegistrationRequest,
    EnvironmentInjection,
    FaultRequest,
    PairRequest,
    PROTOCOL_VERSION,
    RoomCreateRequest,
    SecureCommandEnvelope,
)
from .security import ClientSession, now_ms
from .service import GatewayService


class RequestBodyLimitMiddleware:
    """Bound API bodies before FastAPI performs JSON parsing or validation."""

    def __init__(self, app: ASGIApp, max_body_size: int) -> None:
        self.app = app
        self.max_body_size = max_body_size

    async def __call__(
        self, scope: Scope, receive: Receive, send: Send
    ) -> None:
        if (
            scope["type"] != "http"
            or not scope["path"].startswith("/api/")
            or scope["method"] not in {"POST", "PUT", "PATCH"}
        ):
            await self.app(scope, receive, send)
            return

        content_length = next(
            (
                value
                for name, value in scope["headers"]
                if name.lower() == b"content-length"
            ),
            None,
        )
        if content_length is not None:
            try:
                declared_size = int(content_length)
            except ValueError:
                declared_size = self.max_body_size + 1
            if declared_size > self.max_body_size:
                await self._send_too_large(scope, receive, send)
                return

        received_size = 0
        chunks: list[bytes] = []
        more_body = True
        while more_body:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            chunk = message.get("body", b"")
            received_size += len(chunk)
            if received_size > self.max_body_size:
                await self._send_too_large(scope, receive, send)
                return
            chunks.append(chunk)
            more_body = bool(message.get("more_body", False))

        consumed = False

        async def limited_receive() -> Message:
            nonlocal consumed
            if not consumed:
                consumed = True
                return {
                    "type": "http.request",
                    "body": b"".join(chunks),
                    "more_body": False,
                }
            return await receive()

        await self.app(scope, limited_receive, send)

    @staticmethod
    async def _send_too_large(
        scope: Scope, receive: Receive, send: Send
    ) -> None:
        response = JSONResponse(
            status_code=413,
            content={
                "error": {
                    "code": "INVALID_COMMAND",
                    "message": "请求正文超过安全限制",
                }
            },
        )
        await response(scope, receive, send)


class TransportSecurityHeadersMiddleware:
    """Attach transport headers without buffering request bodies."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(
        self, scope: Scope, receive: Receive, send: Send
    ) -> None:
        async def send_with_security_headers(message: Message) -> None:
            if (
                scope["type"] == "http"
                and scope["path"].startswith("/api/")
                and message["type"] == "http.response.start"
            ):
                headers = MutableHeaders(scope=message)
                headers["Cache-Control"] = "no-store"
                headers["Strict-Transport-Security"] = (
                    "max-age=31536000; includeSubDomains"
                )
                headers["X-Content-Type-Options"] = "nosniff"
                headers["Referrer-Policy"] = "no-referrer"
            await send(message)

        await self.app(scope, receive, send_with_security_headers)


def _transport_capabilities(config: GatewayConfig) -> list[dict[str, object]]:
    return [
        {
            "id": "https-rest",
            "enabled": True,
            "mode": "request-response",
            "security": "TLS 1.2+, Bearer, AES-256-GCM commands",
        },
        {
            "id": "wss",
            "enabled": True,
            "mode": "bidirectional-events",
            "security": "TLS 1.2+, Bearer, AES-256-GCM commands",
        },
        {
            "id": "https-sse",
            "enabled": True,
            "mode": "server-events",
            "security": "TLS 1.2+, Bearer",
        },
        {
            "id": "mqtt5-tls",
            "available": True,
            "enabled": config.mqtt_enabled,
            "mode": "publish-subscribe",
            "security": "TLS 1.2+, broker authentication, AES-256-GCM commands",
        },
    ]


def _encode_sse(event: dict[str, Any]) -> bytes:
    event_type = str(event.get("type", "message"))
    payload = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
    return f"event: {event_type}\ndata: {payload}\n\n".encode("utf-8")


async def _sse_event_stream(
    gateway: GatewayService,
    credential: str,
    disconnected: Callable[[], Awaitable[bool]],
) -> AsyncIterator[bytes]:
    queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=64)

    async def sink(event: dict[str, Any]) -> None:
        if queue.full():
            try:
                queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
        queue.put_nowait(event)

    gateway.add_sink(sink)
    try:
        yield _encode_sse(
            {
                "protocolVersion": PROTOCOL_VERSION,
                "type": "heartbeat",
                "timestamp": now_ms(),
            }
        )
        while not await disconnected():
            try:
                session = gateway.sessions.authenticate(credential)
            except GatewayError:
                return
            timeout = min(15.0, gateway.sessions.remaining_seconds(session))
            if timeout <= 0:
                return
            try:
                event = await asyncio.wait_for(queue.get(), timeout=timeout)
            except TimeoutError:
                event = {
                    "protocolVersion": PROTOCOL_VERSION,
                    "type": "heartbeat",
                    "timestamp": now_ms(),
                }
            yield _encode_sse(event)
    finally:
        gateway.remove_sink(sink)


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
            "transports": _transport_capabilities(effective_config),
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

    @app.get("/api/v1/rooms")
    async def rooms(
        session: ClientSession = Depends(require_session),
    ) -> dict[str, object]:
        del session
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "rooms": gateway.rooms_snapshot(),
        }

    @app.post("/api/v1/rooms")
    async def create_room(
        body: RoomCreateRequest,
        session: ClientSession = Depends(require_session),
    ) -> dict[str, object]:
        room = await gateway.create_room(session, body)
        await gateway.broadcast(
            {
                "protocolVersion": PROTOCOL_VERSION,
                "type": "room.created",
                "room": room,
            }
        )
        return {"room": room}

    @app.post("/api/v1/devices/register")
    async def register_device(
        body: DeviceRegistrationRequest,
        session: ClientSession = Depends(require_session),
    ) -> dict[str, object]:
        device = await gateway.register_device(session, body)
        await gateway.broadcast(gateway.state_event(device))
        return {
            "deviceId": body.deviceId,
            "accepted": True,
            "online": bool(device["online"]),
        }

    @app.delete("/api/v1/devices/{device_id}")
    async def delete_device(
        device_id: str,
        session: ClientSession = Depends(require_session),
    ) -> dict[str, object]:
        removed = await gateway.delete_device(session, device_id)
        await gateway.broadcast(
            {
                "protocolVersion": PROTOCOL_VERSION,
                "type": "device.removed",
                "timestamp": now_ms(),
                "deviceId": removed["id"],
            }
        )
        return {"deviceId": removed["id"], "deleted": True}

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

    @app.post("/api/v1/commands")
    async def commands(
        body: SecureCommandEnvelope,
        session: ClientSession = Depends(require_session),
    ) -> dict[str, object]:
        result, state_events = await gateway.process_command(session, body)
        for event in state_events:
            await gateway.broadcast(event)
        return result

    @app.get("/api/v1/events")
    async def server_sent_events(
        request: Request,
        authorization: Annotated[str | None, Header()] = None,
    ) -> StreamingResponse:
        credential = _extract_bearer(authorization)
        gateway.sessions.authenticate(credential)
        return StreamingResponse(
            _sse_event_stream(gateway, credential, request.is_disconnected),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-store",
                "X-Accel-Buffering": "no",
                "X-Content-Type-Options": "nosniff",
            },
        )

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

    # Register after the header middleware so this pure ASGI guard is outermost
    # and observes body chunks before FastAPI or BaseHTTPMiddleware buffers them.
    app.add_middleware(
        RequestBodyLimitMiddleware,
        max_body_size=effective_config.max_transport_message_bytes,
    )
    app.add_middleware(TransportSecurityHeadersMiddleware)

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

    @app.get("/", response_class=HTMLResponse)
    async def dashboard() -> HTMLResponse:
        return HTMLResponse(_ADMIN_DASHBOARD_HTML_V2)

    @app.get("/admin/v1/dashboard")
    async def dashboard_snapshot(
        authorized: None = Depends(require_admin),
    ) -> dict[str, object]:
        del authorized
        logs = service.storage.get_logs(None, 20)
        devices = service.devices.snapshot()
        alerts = service.storage.get_alerts(20)
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "serverTime": now_ms(),
            "pairing": {
                "code": service.sessions.pairing_code,
                "expiresInSeconds": service.sessions.pairing_expires_in,
            },
            "devices": devices,
            "logs": logs["items"],
            "alerts": alerts,
            "briefing": _build_gateway_briefing_v2(
                devices,
                alerts,
                logs["items"],
                service.sessions.pairing_expires_in,
            ),
            "security": [
                {"name": "传输层", "value": "HTTPS / WSS"},
                {"name": "数据层", "value": "AES-256-GCM"},
                {"name": "密钥层", "value": "HUKS"},
            ],
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

    @app.post("/admin/v1/devices/provision")
    async def provision_device(
        body: DeviceProvisionRequest,
        authorized: None = Depends(require_admin),
    ) -> dict[str, object]:
        del authorized
        return {
            "gatewayProofFormat": "jws",
            "gatewayProof": service.issue_registration_proof(body),
        }

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


def _build_gateway_briefing(
    devices: list[dict[str, Any]],
    alerts: list[dict[str, Any]],
    logs: list[dict[str, Any]],
    pairing_expires_in: int,
) -> list[dict[str, str]]:
    offline = [item for item in devices if not item.get("online", False)]
    env = next(
        (item for item in devices if item.get("type") == "environment"),
        None,
    )
    door = next(
        (item for item in devices if item.get("type") == "doorLock"),
        None,
    )
    ac = next(
        (item for item in devices if item.get("type") == "airConditioner"),
        None,
    )
    briefing: list[dict[str, str]] = []

    if offline:
        names = "、".join(
            str(item.get("name", item.get("id", ""))) for item in offline
        )
        briefing.append(
            {
                "level": "risk",
                "title": "设备连接异常",
                "body": f"{names} 当前离线。演示时可以说明：APP 不会伪造成功状态，必须等待网关权威快照恢复。",
            }
        )
    else:
        briefing.append(
            {
                "level": "safe",
                "title": "设备链路稳定",
                "body": f"{len(devices)} 台模拟设备在线，网关正在作为家庭设备状态的唯一权威来源。",
            }
        )

    if env is not None:
        temperature = float(env.get("temperatureCelsius", 0))
        humidity = float(env.get("humidityPercent", 0))
        if temperature >= 29 or humidity >= 68:
            briefing.append(
                {
                    "level": "warn",
                    "title": "环境舒适度偏低",
                    "body": f"当前 {temperature:.1f}°C / {humidity:.0f}%RH，建议开启空调制冷或除湿，并观察网关状态回传。",
                }
            )
        else:
            briefing.append(
                {
                    "level": "safe",
                    "title": "环境状态正常",
                    "body": f"当前 {temperature:.1f}°C / {humidity:.0f}%RH，家庭环境处于可接受范围。",
                }
            )

    if door is not None:
        locked = bool(door.get("locked", False))
        battery = int(door.get("batteryPercent", 100))
        jammed = bool(door.get("jammed", False))
        if not locked or battery <= 20 or jammed:
            details = []
            if not locked:
                details.append("门锁未锁定")
            if battery <= 20:
                details.append("电量偏低")
            if jammed:
                details.append("存在卡滞")
            briefing.append(
                {
                    "level": "risk",
                    "title": "门锁安全需要关注",
                    "body": "、".join(details)
                    + "。建议优先处理门锁状态；管理端只展示风险，不直接替用户执行解锁。",
                }
            )
        else:
            briefing.append(
                {
                    "level": "safe",
                    "title": "门锁状态安全",
                    "body": "入户门锁已锁定，电量正常；解锁操作仍需要用户二次确认。",
                }
            )

    if ac is not None and env is not None:
        if ac.get("power") and env.get("presence"):
            briefing.append(
                {
                    "level": "info",
                    "title": "空调联动可解释",
                    "body": "网关会根据空调模式让环境值逐步收敛，适合演示“控制后状态不是 APP 伪造，而是网关推送”。",
                }
            )

    if alerts:
        briefing.append(
            {
                "level": "warn",
                "title": "存在安全/设备告警",
                "body": f"最近有 {len(alerts)} 条告警，可结合审计日志说明网关会记录异常但不泄露敏感凭据。",
            }
        )

    if pairing_expires_in <= 60:
        briefing.append(
            {
                "level": "warn",
                "title": "配对码即将过期",
                "body": "一次性配对码有效期不足 60 秒。过期后需要使用网关新生成的配对码，避免固定口令长期复用。",
            }
        )

    if logs:
        briefing.append(
            {
                "level": "info",
                "title": "审计链路可追踪",
                "body": "近期控制命令已写入审计日志，可用于展示操作时间、设备、动作和结果。",
            }
        )

    return briefing[:6]


def _build_gateway_briefing_v2(
    devices: list[dict[str, Any]],
    alerts: list[dict[str, Any]],
    logs: list[dict[str, Any]],
    pairing_expires_in: int,
) -> list[dict[str, str]]:
    offline = [item for item in devices if not item.get("online", False)]
    env = next(
        (item for item in devices if item.get("type") == "environment"),
        None,
    )
    door = next(
        (item for item in devices if item.get("type") == "doorLock"),
        None,
    )
    briefing: list[dict[str, str]] = []

    if offline:
        names = "、".join(
            str(item.get("name", item.get("id", ""))) for item in offline
        )
        briefing.append(
            {
                "level": "risk",
                "title": "有设备离线",
                "body": f"{names} 当前离线。演示时可以观察 App 是否停止控制，并查看这里的设备状态和告警记录。",
            }
        )
    else:
        briefing.append(
            {
                "level": "safe",
                "title": "设备连接正常",
                "body": f"当前 {len(devices)} 台模拟设备在线。这里显示的是网关侧记录的设备状态。",
            }
        )

    if env is not None:
        temperature = float(env.get("temperatureCelsius", 0))
        humidity = float(env.get("humidityPercent", 0))
        if temperature >= 29 or humidity >= 68:
            briefing.append(
                {
                    "level": "warn",
                    "title": "环境偏闷热",
                    "body": f"当前 {temperature:.1f}°C / {humidity:.0f}%RH。可以在 App 里尝试空调控制，再回到这里看状态变化。",
                }
            )
        else:
            briefing.append(
                {
                    "level": "safe",
                    "title": "环境状态正常",
                    "body": f"当前 {temperature:.1f}°C / {humidity:.0f}%RH，环境传感器数据正常。",
                }
            )

    if door is not None:
        locked = bool(door.get("locked", False))
        battery = int(door.get("batteryPercent", 100))
        jammed = bool(door.get("jammed", False))
        if not locked or battery <= 20 or jammed:
            details = []
            if not locked:
                details.append("门锁未锁")
            if battery <= 20:
                details.append("电量偏低")
            if jammed:
                details.append("卡滞")
            briefing.append(
                {
                    "level": "risk",
                    "title": "门锁需要关注",
                    "body": "、".join(details)
                    + "。这个页面只用于查看和测试，不替用户执行解锁。",
                }
            )
        else:
            briefing.append(
                {
                    "level": "safe",
                    "title": "门锁状态正常",
                    "body": "入户门锁已锁定，电量正常。App 解锁仍需要二次确认。",
                }
            )

    if alerts:
        briefing.append(
            {
                "level": "warn",
                "title": "存在告警记录",
                "body": f"最近有 {len(alerts)} 条告警，可以结合下面的告警表和审计记录一起演示。",
            }
        )

    if pairing_expires_in <= 60:
        briefing.append(
            {
                "level": "warn",
                "title": "配对码快过期",
                "body": "一次性配对码剩余不足 60 秒。过期后需要使用网关新生成的配对码。",
            }
        )

    if logs:
        briefing.append(
            {
                "level": "info",
                "title": "已有操作记录",
                "body": "最近的控制或测试操作会显示在审计记录中，方便演示状态变化不是只改了界面。",
            }
        )

    return briefing[:6]


_ADMIN_DASHBOARD_HTML = """
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DevControl 网关可视化</title>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; font-family: "Segoe UI", "Microsoft YaHei", sans-serif; background: #eef6fb; color: #13293d; }
    header { padding: 22px 26px; background: #197fc7; color: white; display: flex; gap: 16px; align-items: flex-end; }
    h1 { margin: 0; font-size: 26px; }
    .sub { margin-top: 6px; color: #d7efff; font-size: 14px; }
    .token { margin-left: auto; display: flex; gap: 8px; }
    input { height: 36px; min-width: 280px; border: 0; border-radius: 8px; padding: 0 10px; }
    button { height: 36px; border: 0; border-radius: 8px; padding: 0 14px; background: #0f5fa8; color: white; font-weight: 700; cursor: pointer; }
    button.secondary { background: #e0f2fe; color: #075985; }
    main { padding: 22px 26px 32px; display: grid; grid-template-columns: 1.2fr .8fr; gap: 18px; }
    section, .metric { background: white; border-radius: 12px; border: 1px solid #d9e2ec; }
    section { padding: 18px; }
    h2 { margin: 0 0 14px; font-size: 18px; }
    .metrics { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 18px; }
    .metric { padding: 16px; }
    .value { font-size: 24px; font-weight: 800; }
    .label, .muted { color: #66788a; font-size: 13px; }
    .devices { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
    .device { border: 1px solid #d9e2ec; border-radius: 10px; padding: 14px; min-height: 122px; }
    .top { display: flex; justify-content: space-between; color: #66788a; font-size: 13px; margin-bottom: 12px; }
    .name { font-size: 17px; font-weight: 800; }
    .state { margin-top: 8px; color: #66788a; line-height: 1.5; }
    .ok { color: #0f9f6e; } .bad { color: #d64545; } .warn { color: #d9822b; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    td, th { padding: 9px 8px; border-bottom: 1px solid #d9e2ec; text-align: left; }
    .stack { display: grid; gap: 18px; }
    .security article { border: 1px solid #d9e2ec; border-radius: 8px; padding: 12px; margin-bottom: 10px; }
    .briefing { display: grid; gap: 10px; }
    .briefing article { border: 1px solid #d9e2ec; border-radius: 8px; padding: 12px; }
    .briefing .risk { border-color: #f0b4b4; background: #fff5f5; }
    .briefing .warn { border-color: #f7d9a4; background: #fffaf0; }
    .briefing .safe { border-color: #a7e3ca; background: #f2fbf7; }
    .briefing .info { border-color: #a8d8f7; background: #f2f8fd; }
    .briefing strong { display: block; margin-bottom: 6px; }
    .actions { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
    #status { margin-top: 10px; color: #66788a; font-size: 13px; min-height: 20px; }
    @media (max-width: 980px) { header { display: block; } .token { margin-top: 14px; } main { grid-template-columns: 1fr; } .metrics, .devices { grid-template-columns: repeat(2, 1fr); } }
  </style>
</head>
<body>
  <header>
    <div><h1>DevControl 网关可视化</h1><div class="sub">管理员端：展示设备真相、审计日志、安全链路和故障注入。</div></div>
    <div class="token"><input id="token" type="password" placeholder="输入启动日志里的 Admin Token"><button id="connect">连接</button></div>
  </header>
  <main>
    <div>
      <div class="metrics">
        <div class="metric"><div class="value" id="pairing">--</div><div class="label">当前配对码</div></div>
        <div class="metric"><div class="value" id="expires">--</div><div class="label">剩余时间</div></div>
        <div class="metric"><div class="value" id="online">--</div><div class="label">在线设备</div></div>
        <div class="metric"><div class="value" id="alerts">--</div><div class="label">告警数量</div></div>
      </div>
      <section><h2>家庭设备状态</h2><div class="devices" id="devices"></div></section>
      <section style="margin-top:18px"><h2>审计日志</h2><table><thead><tr><th>时间</th><th>设备</th><th>动作</th><th>结果</th></tr></thead><tbody id="logs"></tbody></table></section>
    </div>
    <div class="stack">
      <section><h2>演示摘要</h2><div class="briefing" id="briefing"></div></section>
      <section><h2>安全链路</h2><div id="security"></div></section>
      <section>
        <h2>故障注入</h2>
        <div class="actions">
          <button class="secondary" data-action="lightOffline">灯光离线</button>
          <button class="secondary" data-action="lightOnline">灯光恢复</button>
          <button class="secondary" data-action="doorFault">门锁低电量/卡滞</button>
          <button class="secondary" data-action="doorRecover">门锁恢复</button>
          <button class="secondary" data-action="envHot">注入闷热环境</button>
          <button class="secondary" data-action="envNormal">恢复舒适环境</button>
        </div>
        <div id="status"></div>
      </section>
      <section><h2>告警</h2><table><thead><tr><th>时间</th><th>设备</th><th>说明</th></tr></thead><tbody id="alertRows"></tbody></table></section>
    </div>
  </main>
  <script>
    const tokenInput = document.querySelector("#token");
    const statusEl = document.querySelector("#status");
    tokenInput.value = localStorage.getItem("devcontrolAdminToken") || "";
    document.querySelector("#connect").addEventListener("click", () => {
      localStorage.setItem("devcontrolAdminToken", tokenInput.value.trim());
      refresh();
    });
    document.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", () => runAction(button.dataset.action)));
    function headers() { return { "X-Admin-Token": tokenInput.value.trim(), "Content-Type": "application/json" }; }
    async function refresh() {
      if (!tokenInput.value.trim()) { statusEl.textContent = "请输入 Admin Token 后连接。"; return; }
      try {
        const response = await fetch("/admin/v1/dashboard", { headers: headers() });
        if (!response.ok) throw new Error("管理员令牌无效或网关未就绪");
        render(await response.json());
        statusEl.textContent = "已同步 " + new Date().toLocaleTimeString();
      } catch (error) { statusEl.textContent = error.message || String(error); }
    }
    function render(data) {
      const devices = data.devices || [];
      document.querySelector("#pairing").textContent = data.pairing.code;
      document.querySelector("#expires").textContent = data.pairing.expiresInSeconds + "s";
      document.querySelector("#online").textContent = devices.filter((item) => item.online).length + "/" + devices.length;
      document.querySelector("#alerts").textContent = (data.alerts || []).length;
      document.querySelector("#devices").innerHTML = devices.map(deviceCard).join("");
      document.querySelector("#logs").innerHTML = (data.logs || []).map(logRow).join("") || emptyRow(4);
      document.querySelector("#alertRows").innerHTML = (data.alerts || []).map(alertRow).join("") || emptyRow(3);
      document.querySelector("#briefing").innerHTML = (data.briefing || []).map(briefingCard).join("");
      document.querySelector("#security").innerHTML = (data.security || []).map((item) => `<article><strong>${item.name}</strong><div class="state">${item.value}</div></article>`).join("");
    }
    function briefingCard(item) {
      return `<article class="${item.level}"><strong>${item.title}</strong><div class="state">${item.body}</div></article>`;
    }
    function deviceCard(device) {
      return `<article class="device"><div class="top"><span>${typeName(device.type)}</span><span class="${device.online ? "ok" : "bad"}">${device.online ? "在线" : "离线"}</span></div><div class="name">${device.name}</div><div class="state">${stateText(device)}</div></article>`;
    }
    function typeName(type) { return { light: "灯光", environment: "环境", airConditioner: "空调", doorLock: "门锁", curtain: "窗帘" }[type] || type; }
    function stateText(device) {
      if (device.type === "light") return `${device.power ? "开启" : "关闭"}，亮度 ${device.brightness}%`;
      if (device.type === "environment") return `${device.temperatureCelsius}°C，${device.humidityPercent}% 湿度，${device.presence ? "有人" : "无人"}`;
      if (device.type === "airConditioner") return `${device.power ? "开启" : "关闭"}，${modeName(device.mode)}，目标 ${device.targetTemperatureCelsius}°C`;
      if (device.type === "doorLock") return `${device.locked ? "已锁" : "未锁"}，电量 ${device.batteryPercent}%${device.jammed ? "，卡滞" : ""}`;
      if (device.type === "curtain") return `打开 ${device.openPercent}%${device.moving ? "，调整中" : ""}`;
      return "";
    }
    function modeName(mode) { return { auto: "自动", cool: "制冷", heat: "制热", dry: "除湿", fan: "送风" }[mode] || mode; }
    function logRow(item) { return `<tr><td>${time(item.timestamp)}</td><td>${item.deviceId}</td><td>${item.action}</td><td class="${item.result === "success" ? "ok" : "bad"}">${item.result}</td></tr>`; }
    function alertRow(item) { return `<tr><td>${time(item.timestamp)}</td><td>${item.deviceId}</td><td class="warn">${item.description}</td></tr>`; }
    function emptyRow(count) { return `<tr><td colspan="${count}">暂无记录</td></tr>`; }
    function time(value) { return new Date(value).toLocaleTimeString(); }
    async function runAction(action) {
      const map = {
        lightOffline: ["/admin/v1/devices/light-living-01/fault", { online: false }],
        lightOnline: ["/admin/v1/devices/light-living-01/fault", { online: true }],
        doorFault: ["/admin/v1/devices/door-entry-01/fault", { jammed: true, batteryPercent: 10 }],
        doorRecover: ["/admin/v1/devices/door-entry-01/fault", { jammed: false, batteryPercent: 92 }],
        envHot: ["/admin/v1/environment/inject", { temperatureCelsius: 30, humidityPercent: 72, illuminanceLux: 30, presence: true }],
        envNormal: ["/admin/v1/environment/inject", { temperatureCelsius: 24, humidityPercent: 55, illuminanceLux: 120, presence: true }]
      };
      const [url, body] = map[action];
      try {
        const response = await fetch(url, { method: "POST", headers: headers(), body: JSON.stringify(body) });
        if (!response.ok) throw new Error("故障注入失败");
        await refresh();
      } catch (error) { statusEl.textContent = error.message || String(error); }
    }
    setInterval(refresh, 3000);
    refresh();
  </script>
</body>
</html>
"""


_ADMIN_DASHBOARD_HTML_V2 = """
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DevControl 网关管理页</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", "Microsoft YaHei", Arial, sans-serif;
      color: #172638;
      background: #f3f7fb;
    }
    header {
      position: sticky;
      top: 0;
      z-index: 5;
      display: flex;
      align-items: flex-end;
      gap: 18px;
      padding: 24px 28px;
      background: #fff;
      border-bottom: 1px solid #dce6f0;
    }
    h1 { margin: 0; font-size: 26px; letter-spacing: 0; }
    h2 { margin: 0 0 12px; font-size: 18px; }
    .sub { margin-top: 7px; color: #627386; font-size: 14px; }
    .token { margin-left: auto; display: flex; gap: 8px; }
    input {
      height: 38px;
      min-width: 300px;
      padding: 0 12px;
      border: 1px solid #ccd8e5;
      border-radius: 8px;
      background: #f8fafc;
    }
    button {
      height: 38px;
      border: 0;
      border-radius: 8px;
      padding: 0 14px;
      background: #1769c2;
      color: #fff;
      font-weight: 700;
      cursor: pointer;
    }
    button.secondary {
      background: #eef5ff;
      color: #155aa5;
      border: 1px solid #cfe0f5;
    }
    button.secondary:hover { background: #dcecff; }
    main {
      display: grid;
      grid-template-columns: minmax(0, 1.25fr) minmax(340px, .75fr);
      gap: 18px;
      padding: 22px 26px 32px;
    }
    section, .metric {
      background: #fff;
      border: 1px solid #d9e2ec;
      border-radius: 10px;
      box-shadow: 0 8px 24px rgba(21, 37, 54, .04);
    }
    section { padding: 18px; }
    .hint {
      margin: -5px 0 14px;
      color: #627386;
      font-size: 13px;
      line-height: 1.6;
    }
    .metrics {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 12px;
      margin-bottom: 18px;
    }
    .metric { padding: 16px; }
    .value { font-size: 24px; font-weight: 800; }
    .label, .state { color: #65758b; font-size: 13px; }
    .overview {
      display: grid;
      grid-template-columns: minmax(300px, .95fr) minmax(300px, 1.05fr);
      gap: 18px;
      margin-bottom: 18px;
    }
    .map-inner {
      position: relative;
      min-height: 268px;
      border: 1px dashed #c9d8e8;
      border-radius: 10px;
      background: linear-gradient(180deg, #fbfdff, #eef6fb);
      overflow: hidden;
    }
    .node {
      position: absolute;
      width: 124px;
      min-height: 74px;
      padding: 10px;
      border: 1px solid #d6e2ee;
      border-radius: 10px;
      background: #fff;
      box-shadow: 0 10px 20px rgba(21, 37, 54, .06);
    }
    .node.gateway {
      left: 50%;
      top: 50%;
      transform: translate(-50%, -50%);
      border-color: #8dbcf4;
      background: #eef6ff;
      text-align: center;
    }
    .node.light { left: 22px; top: 22px; }
    .node.env { right: 22px; top: 22px; }
    .node.ac { left: 22px; bottom: 22px; }
    .node.door { right: 22px; bottom: 22px; }
    .node-title { margin-bottom: 7px; font-weight: 800; }
    .node-state { color: #65758b; font-size: 12px; line-height: 1.45; }
    .devices { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
    .device {
      min-height: 122px;
      padding: 14px;
      border: 1px solid #d9e2ec;
      border-radius: 10px;
    }
    .top {
      display: flex;
      justify-content: space-between;
      margin-bottom: 12px;
      color: #65758b;
      font-size: 13px;
    }
    .name { font-size: 17px; font-weight: 800; }
    .device .state { margin-top: 8px; line-height: 1.5; }
    .ok { color: #0f8f66; }
    .bad { color: #d64545; }
    .warn { color: #d9822b; }
    .stack { display: grid; gap: 18px; }
    .briefing { display: grid; gap: 10px; }
    .briefing article {
      padding: 12px;
      border: 1px solid #d9e2ec;
      border-radius: 8px;
    }
    .briefing strong { display: block; margin-bottom: 6px; }
    .briefing .risk { border-color: #f0b4b4; background: #fff5f5; }
    .briefing .warn { border-color: #f7d9a4; background: #fffaf0; }
    .briefing .safe { border-color: #a7e3ca; background: #f2fbf7; }
    .briefing .info { border-color: #a8d8f7; background: #f2f8fd; }
    .security-path { display: grid; gap: 8px; }
    .security-step {
      display: grid;
      grid-template-columns: 28px 1fr;
      gap: 10px;
      align-items: start;
      padding: 10px;
      border: 1px solid #d9e2ec;
      border-radius: 8px;
      background: #fbfdff;
    }
    .badge {
      width: 28px;
      height: 28px;
      border-radius: 50%;
      display: grid;
      place-items: center;
      background: #1769c2;
      color: #fff;
      font-size: 13px;
      font-weight: 800;
    }
    .actions { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
    .action-note { margin: -4px 0 12px; color: #65758b; font-size: 12px; line-height: 1.5; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    td, th { padding: 9px 8px; border-bottom: 1px solid #d9e2ec; text-align: left; }
    #status { min-height: 20px; margin-top: 10px; color: #65758b; font-size: 13px; }
    @media (max-width: 1100px) { .overview { grid-template-columns: 1fr; } }
    @media (max-width: 980px) {
      header { display: block; }
      .token { margin-top: 14px; }
      main { grid-template-columns: 1fr; }
      .metrics, .devices { grid-template-columns: repeat(2, 1fr); }
    }
    @media (max-width: 620px) {
      main { padding: 16px; }
      .metrics, .devices { grid-template-columns: 1fr; }
      .token { display: grid; }
      input { min-width: 0; width: 100%; }
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>DevControl 网关管理页</h1>
      <div class="sub">用于演示虚拟网关、设备状态、安全记录和测试场景。</div>
    </div>
    <div class="token">
      <input id="token" type="password" placeholder="输入启动日志里的 Admin Token">
      <button id="connect">连接</button>
    </div>
  </header>
  <main>
    <div>
      <div class="metrics">
        <div class="metric"><div class="value" id="pairing">--</div><div class="label">当前配对码</div></div>
        <div class="metric"><div class="value" id="expires">--</div><div class="label">剩余时间</div></div>
        <div class="metric"><div class="value" id="online">--</div><div class="label">在线设备</div></div>
        <div class="metric"><div class="value" id="alerts">--</div><div class="label">告警数量</div></div>
      </div>
      <div class="overview">
        <section>
          <h2>网关与设备</h2>
          <div class="hint">这里展示网关正在管理的模拟家居设备。App 侧看到的状态会跟这里同步。</div>
          <div class="map-inner" id="map"></div>
        </section>
        <section>
          <h2>设备状态</h2>
          <div class="hint">用于确认设备是否在线，以及灯光、环境、空调、门锁的当前状态。</div>
          <div class="devices" id="devices"></div>
        </section>
      </div>
      <section>
        <h2>审计记录</h2>
        <div class="hint">记录设备控制和测试结果，演示时可以用来说明操作不是只改了界面。</div>
        <table>
          <thead><tr><th>时间</th><th>设备</th><th>动作</th><th>结果</th></tr></thead>
          <tbody id="logs"></tbody>
        </table>
      </section>
    </div>
    <div class="stack">
      <section><h2>当前提示</h2><div class="briefing" id="briefing"></div></section>
      <section><h2>安全流程</h2><div class="security-path" id="security"></div></section>
      <section>
        <h2>测试场景与结果</h2>
        <div class="action-note">这些按钮只用于演示。点击后优先看左侧设备状态、下方告警和 App 里的变化；审计记录主要记录 App 发出的控制命令。</div>
        <div class="actions">
          <button class="secondary" data-action="lightOffline">灯光离线</button>
          <button class="secondary" data-action="lightOnline">灯光恢复</button>
          <button class="secondary" data-action="doorFault">门锁低电量/卡滞</button>
          <button class="secondary" data-action="doorRecover">门锁恢复</button>
          <button class="secondary" data-action="envHot">闷热环境</button>
          <button class="secondary" data-action="envNormal">恢复环境</button>
        </div>
        <div id="status"></div>
        <h2 style="margin-top:16px">最近告警</h2>
        <table>
          <thead><tr><th>时间</th><th>设备</th><th>说明</th></tr></thead>
          <tbody id="alertRows"></tbody>
        </table>
      </section>
    </div>
  </main>
  <script>
    const tokenInput = document.querySelector("#token");
    const statusEl = document.querySelector("#status");
    tokenInput.value = localStorage.getItem("devcontrolAdminToken") || "";
    document.querySelector("#connect").addEventListener("click", () => {
      localStorage.setItem("devcontrolAdminToken", tokenInput.value.trim());
      refresh();
    });
    document.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", () => runAction(button.dataset.action)));
    function headers() { return { "X-Admin-Token": tokenInput.value.trim(), "Content-Type": "application/json" }; }
    async function refresh() {
      if (!tokenInput.value.trim()) { statusEl.textContent = "请输入 Admin Token 后连接。"; return; }
      try {
        const response = await fetch("/admin/v1/dashboard", { headers: headers() });
        if (!response.ok) throw new Error("Admin Token 无效，或网关尚未准备好。");
        render(await response.json());
        statusEl.textContent = "已同步 " + new Date().toLocaleTimeString();
      } catch (error) {
        statusEl.textContent = error.message || String(error);
      }
    }
    function render(data) {
      const devices = data.devices || [];
      document.querySelector("#pairing").textContent = data.pairing.code;
      document.querySelector("#expires").textContent = data.pairing.expiresInSeconds + "s";
      document.querySelector("#online").textContent = devices.filter((item) => item.online).length + "/" + devices.length;
      document.querySelector("#alerts").textContent = (data.alerts || []).length;
      document.querySelector("#map").innerHTML = mapNodes(devices);
      document.querySelector("#devices").innerHTML = devices.map(deviceCard).join("");
      document.querySelector("#logs").innerHTML = (data.logs || []).map(logRow).join("") || emptyRow(4);
      document.querySelector("#alertRows").innerHTML = (data.alerts || []).map(alertRow).join("") || emptyRow(3);
      document.querySelector("#briefing").innerHTML = (data.briefing || []).map(briefingCard).join("");
      document.querySelector("#security").innerHTML = securitySteps();
    }
    function mapNodes(devices) {
      const byType = {};
      devices.forEach((device) => byType[device.type] = device);
      return `
        <article class="node gateway"><div class="node-title">虚拟网关</div><div class="node-state">HTTPS / WSS<br>维护端口 18444</div></article>
        ${mapNode("light", byType.light)}
        ${mapNode("env", byType.environment)}
        ${mapNode("ac", byType.airConditioner)}
        ${mapNode("door", byType.doorLock)}
      `;
    }
    function mapNode(slot, device) {
      if (!device) return `<article class="node ${slot}"><div class="node-title">未接入</div><div class="node-state">暂无设备</div></article>`;
      return `<article class="node ${slot}"><div class="node-title">${typeName(device.type)}</div><div class="node-state">${device.name}<br><span class="${device.online ? "ok" : "bad"}">${device.online ? "在线" : "离线"}</span></div></article>`;
    }
    function securitySteps() {
      const steps = [
        ["一次性配对码", "5 分钟有效，配对成功或过期后会轮换。"],
        ["HTTPS / WSS", "App 与网关之间使用加密连接。"],
        ["命令加密", "控制命令使用 AES-256-GCM 封装。"],
        ["本地保护", "App 侧会话材料由 HUKS 保护。"],
        ["审计记录", "关键操作和异常写入网关日志。"]
      ];
      return steps.map((step, index) => `<article class="security-step"><div class="badge">${index + 1}</div><div><strong>${step[0]}</strong><div class="state">${step[1]}</div></div></article>`).join("");
    }
    function briefingCard(item) {
      return `<article class="${item.level}"><strong>${item.title}</strong><div class="state">${item.body}</div></article>`;
    }
    function deviceCard(device) {
      return `<article class="device"><div class="top"><span>${typeName(device.type)}</span><span class="${device.online ? "ok" : "bad"}">${device.online ? "在线" : "离线"}</span></div><div class="name">${device.name}</div><div class="state">${stateText(device)}</div></article>`;
    }
    function typeName(type) {
      return { light: "灯光", environment: "环境", airConditioner: "空调", doorLock: "门锁" }[type] || type;
    }
    function stateText(device) {
      if (device.type === "light") return `${device.power ? "开启" : "关闭"}，亮度 ${device.brightness}%`;
      if (device.type === "environment") return `${device.temperatureCelsius}°C，${device.humidityPercent}% 湿度，${device.presence ? "有人" : "无人"}`;
      if (device.type === "airConditioner") return `${device.power ? "开启" : "关闭"}，${modeName(device.mode)}，目标 ${device.targetTemperatureCelsius}°C`;
      if (device.type === "doorLock") return `${device.locked ? "已锁" : "未锁"}，电量 ${device.batteryPercent}%${device.jammed ? "，卡滞" : ""}`;
      return "";
    }
    function modeName(mode) {
      return { auto: "自动", cool: "制冷", heat: "制热", dry: "除湿", fan: "送风" }[mode] || mode;
    }
    function logRow(item) {
      return `<tr><td>${time(item.timestamp)}</td><td>${item.deviceId}</td><td>${item.action}</td><td class="${item.result === "success" ? "ok" : "bad"}">${item.result}</td></tr>`;
    }
    function alertRow(item) {
      return `<tr><td>${time(item.timestamp)}</td><td>${item.deviceId}</td><td class="warn">${item.description}</td></tr>`;
    }
    function emptyRow(count) { return `<tr><td colspan="${count}">暂无记录</td></tr>`; }
    function time(value) { return new Date(value).toLocaleTimeString(); }
    async function runAction(action) {
      const map = {
        lightOffline: ["/admin/v1/devices/light-living-01/fault", { online: false }],
        lightOnline: ["/admin/v1/devices/light-living-01/fault", { online: true }],
        doorFault: ["/admin/v1/devices/door-entry-01/fault", { jammed: true, batteryPercent: 10 }],
        doorRecover: ["/admin/v1/devices/door-entry-01/fault", { jammed: false, batteryPercent: 92 }],
        envHot: ["/admin/v1/environment/inject", { temperatureCelsius: 30, humidityPercent: 72, illuminanceLux: 30, presence: true }],
        envNormal: ["/admin/v1/environment/inject", { temperatureCelsius: 24, humidityPercent: 55, illuminanceLux: 120, presence: true }]
      };
      const [url, body] = map[action];
      try {
        const response = await fetch(url, { method: "POST", headers: headers(), body: JSON.stringify(body) });
        if (!response.ok) throw new Error("测试场景执行失败。");
        await refresh();
      } catch (error) {
        statusEl.textContent = error.message || String(error);
      }
    }
    setInterval(refresh, 3000);
    refresh();
  </script>
</body>
</html>
"""
