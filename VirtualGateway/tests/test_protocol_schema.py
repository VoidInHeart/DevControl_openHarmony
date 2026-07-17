from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator

from devcontrol_gateway.config import GatewayConfig
from devcontrol_gateway.models import PROTOCOL_VERSION
from devcontrol_gateway.security import encrypt_payload, now_ms
from devcontrol_gateway.service import GatewayService


SCHEMA_PATH = (
    Path(__file__).resolve().parents[1] / "protocol" / "protocol-v1.schema.json"
)


def validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def test_default_device_snapshots_match_shared_schema(tmp_path: Path) -> None:
    gateway = GatewayService(
        GatewayConfig(
            database=tmp_path / "schema.db",
            pairing_code="123456",
            enable_background_tasks=False,
        )
    )
    try:
        contract = validator()
        for device in gateway.devices.snapshot():
            contract.validate(device)
    finally:
        gateway.storage.close()


def test_secure_command_matches_shared_schema() -> None:
    header: dict[str, object] = {
        "protocolVersion": PROTOCOL_VERSION,
        "messageId": "schema-command-message-0001",
        "deviceId": "light-living-01",
        "timestamp": now_ms(),
        "type": "command.request",
        "action": "setPower",
        "expectedStateVersion": 1,
    }
    envelope = {
        **header,
        **encrypt_payload(bytes(range(32)), {"power": True}, header),
    }
    validator().validate(envelope)


def test_gateway_events_match_shared_schema(tmp_path: Path) -> None:
    gateway = GatewayService(
        GatewayConfig(
            database=tmp_path / "events.db",
            pairing_code="123456",
            enable_background_tasks=False,
        )
    )
    try:
        contract = validator()
        device = gateway.devices.snapshot()[0]
        contract.validate(gateway.state_event(device))
        contract.validate(
            {
                "protocolVersion": "1.0",
                "type": "heartbeat",
                "timestamp": now_ms(),
            }
        )
        gateway.devices.inject_fault(
            "door-entry-01", {"batteryPercent": 10}
        )
        for alert in gateway.devices.drain_alerts():
            contract.validate(alert)
    finally:
        gateway.storage.close()
