from __future__ import annotations

import asyncio
import time
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from devcontrol_gateway.app import create_app
from devcontrol_gateway.composition import default_drivers
from devcontrol_gateway.config import GatewayConfig
from devcontrol_gateway.errors import AUTH_FAILED, RATE_LIMITED
from devcontrol_gateway.models import PROTOCOL_VERSION, SecureCommandEnvelope
from devcontrol_gateway.security import (
    ClientSession,
    SessionRegistry,
    encrypt_payload,
    now_ms,
)
from devcontrol_gateway.service import GatewayService


def make_config(tmp_path: Path) -> GatewayConfig:
    return GatewayConfig(
        database=tmp_path / "gateway.db",
        initial_pairing_code="123456",
        admin_token="test-admin-token",
        enable_background_tasks=False,
    )


def pair(service: GatewayService) -> tuple[str, ClientSession]:
    response = service.sessions.pair("127.0.0.1", f"test-client-{uuid4()}", "123456")
    session = service.sessions.authenticate(response.credential)
    return response.credential, session


def command(
    session: ClientSession,
    *,
    device_id: str,
    action: str,
    expected_version: int | None,
    payload: dict[str, object],
    message_id: str | None = None,
    timestamp: int | None = None,
) -> SecureCommandEnvelope:
    header: dict[str, object] = {
        "protocolVersion": PROTOCOL_VERSION,
        "messageId": message_id or f"msg-{uuid4().hex}",
        "deviceId": device_id,
        "timestamp": timestamp or now_ms(),
        "type": "command.request",
        "action": action,
        "expectedStateVersion": expected_version,
    }
    encrypted = encrypt_payload(session.data_key, payload, header)
    return SecureCommandEnvelope(**header, **encrypted)


def process(
    service: GatewayService,
    session: ClientSession,
    envelope: SecureCommandEnvelope,
) -> tuple[dict[str, object], list[dict[str, object]]]:
    return asyncio.run(service.process_command(session, envelope))


@pytest.fixture
def service(tmp_path: Path):
    gateway = GatewayService(make_config(tmp_path))
    yield gateway
    asyncio.run(gateway.stop())


def test_pairing_and_authentication(service: GatewayService) -> None:
    credential, session = pair(service)
    assert len(credential) >= 40
    assert session.client_id.startswith("test-client-")
    assert len(session.data_key) == 32
    with pytest.raises(Exception) as invalid:
        service.sessions.authenticate("not-a-real-token")
    assert getattr(invalid.value, "code", None) == AUTH_FAILED


def test_pairing_rate_limit() -> None:
    registry = SessionRegistry("123456")
    for _ in range(4):
        with pytest.raises(Exception) as failure:
            registry.pair("source-a", "client-12345678", "000000")
        assert failure.value.code == AUTH_FAILED
    with pytest.raises(Exception) as locked:
        registry.pair("source-a", "client-12345678", "000000")
    assert locked.value.code == RATE_LIMITED
    assert locked.value.retry_after_seconds == 600


def test_initial_pairing_code_rotates_after_success() -> None:
    generated_codes = iter(["654321"])
    registry = SessionRegistry(
        "123456",
        pairing_code_factory=lambda: next(generated_codes),
    )
    registry.pair("source-a", "client-12345678", "123456")
    assert registry.pairing_code == "654321"
    with pytest.raises(Exception) as reused:
        registry.pair("source-b", "client-87654321", "123456")
    assert reused.value.code == AUTH_FAILED


def test_expired_pairing_code_rotates_without_sleeping() -> None:
    current_time = [100.0]
    generated_codes = iter(["654321"])
    registry = SessionRegistry(
        "123456",
        clock=lambda: current_time[0],
        pairing_code_factory=lambda: next(generated_codes),
    )
    assert registry.pairing_expires_in == 300
    current_time[0] += 301
    assert registry.pairing_code == "654321"


def test_credential_expires_at_the_configured_boundary() -> None:
    current_time_ms = [1_700_000_000_000]
    registry = SessionRegistry(
        "123456",
        wall_clock_ms=lambda: current_time_ms[0],
        credential_ttl_seconds=60,
    )
    response = registry.pair("source-a", "client-12345678", "123456")
    assert response.expiresAt == response.issuedAt + 60_000
    assert registry.authenticate(response.credential).expires_at == response.expiresAt

    current_time_ms[0] = response.expiresAt
    with pytest.raises(Exception) as expired:
        registry.authenticate(response.credential)
    assert expired.value.code == AUTH_FAILED


def test_open_websocket_rejects_commands_after_credential_expiry(
    tmp_path: Path,
) -> None:
    current_time_ms = [1_700_000_000_000]
    config = make_config(tmp_path)
    gateway = GatewayService(config)
    gateway.sessions = SessionRegistry(
        "123456",
        wall_clock_ms=lambda: current_time_ms[0],
        credential_ttl_seconds=1,
    )
    credential, _ = pair(gateway)

    with TestClient(create_app(config, gateway)) as client:
        with client.websocket_connect(
            "/ws/v1/events",
            headers={"Authorization": f"Bearer {credential}"},
        ) as socket:
            assert socket.receive_json()["type"] == "heartbeat"
            current_time_ms[0] += 1_000
            socket.send_json({})
            with pytest.raises(WebSocketDisconnect) as closed:
                socket.receive_json()
            assert closed.value.code == 4401

        response = client.get(
            "/api/v1/devices",
            headers={"Authorization": f"Bearer {credential}"},
        )
        assert response.status_code == 401
        assert response.json()["error"]["code"] == AUTH_FAILED


def test_light_command_is_authoritative_and_idempotent(
    service: GatewayService,
) -> None:
    _, session = pair(service)
    light = service.devices.get("light-living-01")
    envelope = command(
        session,
        device_id=light["id"],
        action="setPower",
        expected_version=light["stateVersion"],
        payload={"power": True},
        message_id="msg-idempotency-0001",
    )
    first, events = process(service, session, envelope)
    first_version = service.devices.get(light["id"])["stateVersion"]
    second, duplicate_events = process(service, session, envelope)
    assert first["success"] is True
    assert events[0]["type"] == "state.changed"
    assert second == first
    assert duplicate_events == []
    assert service.devices.get(light["id"])["stateVersion"] == first_version


def test_tamper_replay_and_state_conflict(service: GatewayService) -> None:
    _, session = pair(service)
    light = service.devices.get("light-living-01")
    original = command(
        session,
        device_id=light["id"],
        action="setBrightness",
        expected_version=light["stateVersion"],
        payload={"brightness": 80},
        message_id="msg-security-original",
    )
    raw = original.model_dump()
    raw["ciphertext"] = ("A" if raw["ciphertext"][0] != "A" else "B") + raw[
        "ciphertext"
    ][1:]
    tampered, _ = process(service, session, SecureCommandEnvelope.model_validate(raw))
    assert tampered["success"] is False
    assert tampered["error"]["code"] == "REPLAY_DETECTED"

    replay_raw = original.model_dump()
    replay_raw["messageId"] = "msg-security-reused-nonce"
    replay, _ = process(
        service, session, SecureCommandEnvelope.model_validate(replay_raw)
    )
    assert replay["error"]["code"] == "REPLAY_DETECTED"

    stale = command(
        session,
        device_id=light["id"],
        action="setPower",
        expected_version=0,
        payload={"power": True},
    )
    conflict, _ = process(service, session, stale)
    assert conflict["error"]["code"] == "STATE_CONFLICT"


def test_expired_message_is_rejected(service: GatewayService) -> None:
    _, session = pair(service)
    light = service.devices.get("light-living-01")
    envelope = command(
        session,
        device_id=light["id"],
        action="setPower",
        expected_version=light["stateVersion"],
        payload={"power": True},
        timestamp=now_ms() - 31_000,
    )
    result, _ = process(service, session, envelope)
    assert result["error"]["code"] == "REPLAY_DETECTED"
    assert service.devices.get(light["id"])["power"] is False


def test_away_scene_returns_per_device_results(
    service: GatewayService,
) -> None:
    _, session = pair(service)
    service.devices.get("light-living-01")["power"] = True
    service.devices.get("ac-living-01")["power"] = True
    service.devices.get("door-entry-01")["locked"] = False
    envelope = command(
        session,
        device_id="scene-away",
        action="executeAway",
        expected_version=None,
        payload={},
    )
    result, events = process(service, session, envelope)
    assert result["success"] is True
    assert len(result["details"]) == 3
    assert all(item["success"] for item in result["details"])
    assert len(events) == 3
    assert service.devices.get("light-living-01")["power"] is False
    assert service.devices.get("ac-living-01")["power"] is False
    assert service.devices.get("door-entry-01")["locked"] is True


def test_home_scene_returns_per_device_results(
    service: GatewayService,
) -> None:
    _, session = pair(service)
    service.devices.get("light-living-01")["power"] = False
    service.devices.get("ac-living-01").update(
        {"power": False, "mode": "heat", "targetTemperatureCelsius": 30}
    )
    service.devices.get("door-entry-01")["locked"] = False
    envelope = command(
        session,
        device_id="scene-home",
        action="executeHome",
        expected_version=None,
        payload={},
    )
    result, events = process(service, session, envelope)
    assert result["success"] is True
    assert len(result["details"]) == 3
    assert all(item["success"] for item in result["details"])
    assert len(events) == 3
    light = service.devices.get("light-living-01")
    ac = service.devices.get("ac-living-01")
    assert light["power"] is True
    assert light["brightness"] == 70
    assert ac["power"] is True
    assert ac["mode"] == "auto"
    assert ac["targetTemperatureCelsius"] == 24
    assert service.devices.get("door-entry-01")["locked"] is True


def test_automation_ac_and_door_behaviour(service: GatewayService) -> None:
    _, session = pair(service)
    light = service.devices.get("light-living-01")
    auto = command(
        session,
        device_id=light["id"],
        action="setAutomationConfig",
        expected_version=light["stateVersion"],
        payload={
            "enabled": True,
            "illuminanceThresholdLux": 100,
            "noPresenceDelaySeconds": 5,
        },
    )
    process(service, session, auto)
    service.devices.inject_environment(
        {
            "temperatureCelsius": None,
            "humidityPercent": None,
            "illuminanceLux": 10,
            "presence": True,
        }
    )
    service.devices.tick()
    assert service.devices.get(light["id"])["power"] is True

    env = service.devices.get("env-living-01")
    ac = service.devices.get("ac-living-01")
    before = env["temperatureCelsius"]
    env["_manualInjectionUntil"] = 0
    ac["power"] = True
    ac["mode"] = "cool"
    ac["targetTemperatureCelsius"] = 16
    service.devices.tick()
    assert env["temperatureCelsius"] < before

    door = service.devices.get("door-entry-01")
    unlock = command(
        session,
        device_id=door["id"],
        action="unlock",
        expected_version=door["stateVersion"],
        payload={},
    )
    process(service, session, unlock)
    door["autoLockAt"] = now_ms() - 1
    service.devices.tick()
    assert door["locked"] is True


def test_sqlite_contains_no_session_secret_columns(
    service: GatewayService,
) -> None:
    for table in ("audit_logs", "alerts", "environment_history"):
        columns = service.storage.table_columns(table)
        joined = " ".join(columns).lower()
        assert "credential" not in joined
        assert "data_key" not in joined
        assert "token" not in joined


def test_rest_and_websocket_contract(tmp_path: Path) -> None:
    config = make_config(tmp_path)
    gateway = GatewayService(config)
    app = create_app(config, gateway)
    with TestClient(app) as client:
        health = client.get("/api/v1/health")
        assert health.status_code == 200
        assert health.json()["protocolVersion"] == "1.0"

        paired = client.post(
            "/api/v1/pair",
            json={
                "protocolVersion": "1.0",
                "pairingCode": "123456",
                "clientId": "rest-client-12345678",
            },
        )
        assert paired.status_code == 200
        credential = paired.json()["credential"]
        session = gateway.sessions.authenticate(credential)
        headers = {"Authorization": f"Bearer {credential}"}
        snapshot = client.get("/api/v1/devices", headers=headers)
        assert snapshot.status_code == 200
        assert len(snapshot.json()["devices"]) == 6
        assert any(item["type"] == "curtain" for item in snapshot.json()["devices"])
        assert any(item["type"] == "fan" for item in snapshot.json()["devices"])

        light = gateway.devices.get("light-living-01")
        envelope = command(
            session,
            device_id=light["id"],
            action="setPower",
            expected_version=light["stateVersion"],
            payload={"power": True},
        )
        with client.websocket_connect("/ws/v1/events", headers=headers) as websocket:
            heartbeat = websocket.receive_json()
            assert heartbeat["type"] == "heartbeat"
            websocket.send_json(envelope.model_dump())
            result = websocket.receive_json()
            event = websocket.receive_json()
            assert result["type"] == "command.result"
            assert result["success"] is True
            assert event["type"] == "state.changed"

        gateway.devices.tick()
        history = client.get(
            "/api/v1/history/environment",
            params={
                "from": now_ms() - 60_000,
                "to": now_ms() + 1_000,
                "limit": 10,
            },
            headers=headers,
        )
        assert history.status_code == 200
        assert history.json()["items"]

        logs = client.get("/api/v1/logs", headers=headers)
        assert logs.status_code == 200
        assert logs.json()["items"]


def test_curtain_secure_command_is_idempotent_and_emits_state(
    service: GatewayService,
) -> None:
    _, session = pair(service)
    curtain = service.devices.get("curtain-living-01")
    envelope = command(
        session,
        device_id=curtain["id"],
        action="setPosition",
        expected_version=curtain["stateVersion"],
        payload={"positionPercent": 40},
        message_id="msg-curtain-idempotency-0001",
    )

    first, events = process(service, session, envelope)
    first_version = service.devices.get(curtain["id"])["stateVersion"]
    duplicate, duplicate_events = process(service, session, envelope)

    assert first["success"] is True
    assert events[0]["type"] == "state.changed"
    assert events[0]["device"]["state"]["targetPositionPercent"] == 40
    assert duplicate == first
    assert duplicate_events == []
    assert service.devices.get(curtain["id"])["stateVersion"] == first_version

    changed = service.devices.tick()
    curtain_events = [item for item in changed if item["id"] == "curtain-living-01"]
    assert curtain_events[0]["state"]["positionPercent"] == 10

    stale = command(
        session,
        device_id=curtain["id"],
        action="close",
        expected_version=0,
        payload={},
    )
    conflict, _ = process(service, session, stale)
    assert conflict["error"]["code"] == "STATE_CONFLICT"


def test_new_virtual_fan_uses_generic_secure_command_path(
    service: GatewayService,
) -> None:
    assert all(
        driver.device_type != "fan"
        for driver in default_drivers(include_demo_extensions=False)
    )
    assert any(
        driver.device_type == "fan"
        for driver in default_drivers(include_demo_extensions=True)
    )
    _, session = pair(service)
    fan = service.devices.get("fan-bedroom-01")
    assert fan["category"]["id"] == "fans"
    assert [control["kind"] for control in fan["controls"]] == [
        "toggle",
        "enum",
        "toggle",
    ]

    power, power_events = process(
        service,
        session,
        command(
            session,
            device_id=fan["id"],
            action="setPower",
            expected_version=fan["stateVersion"],
            payload={"power": True},
        ),
    )
    assert power["success"] is True
    assert power_events[0]["device"]["state"]["power"] is True

    fan = service.devices.get("fan-bedroom-01")
    speed, speed_events = process(
        service,
        session,
        command(
            session,
            device_id=fan["id"],
            action="setSpeed",
            expected_version=fan["stateVersion"],
            payload={"speed": "high"},
        ),
    )
    assert speed["success"] is True
    assert speed_events[0]["device"]["state"]["speed"] == "high"

    fan = service.devices.get("fan-bedroom-01")
    invalid, invalid_events = process(
        service,
        session,
        command(
            session,
            device_id=fan["id"],
            action="setSpeed",
            expected_version=fan["stateVersion"],
            payload={"speed": "turbo"},
        ),
    )
    assert invalid["error"]["code"] == "INVALID_COMMAND"
    assert invalid_events == []
