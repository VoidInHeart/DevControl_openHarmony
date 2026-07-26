from __future__ import annotations

import asyncio
import json
import os
import ssl
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest
from fastapi import FastAPI

from devcontrol_gateway.__main__ import _business_server_config
from devcontrol_gateway.app import create_app
from devcontrol_gateway.config import GatewayConfig
from devcontrol_gateway.models import PROTOCOL_VERSION, SecureCommandEnvelope
from devcontrol_gateway.mqtt_transport import MqttBridge
from devcontrol_gateway.security import encrypt_payload, now_ms
from devcontrol_gateway.service import GatewayService


GATEWAY_SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
SIGNING_ADMIN_ROOT = Path(__file__).resolve().parents[2] / "SigningAdmin"


class FakeMqttClient:
    def __init__(self) -> None:
        self.on_connect: Any = None
        self.on_disconnect: Any = None
        self.on_message: Any = None
        self.tls_context: ssl.SSLContext | None = None
        self.tls_insecure = True
        self.username: tuple[str, str] | None = None
        self.connected: tuple[str, int, int] | None = None
        self.subscriptions: list[tuple[str, int]] = []
        self.published: list[tuple[str, str, int, bool]] = []
        self.running = False

    def tls_set_context(self, context: ssl.SSLContext) -> None:
        self.tls_context = context

    def tls_insecure_set(self, value: bool) -> None:
        self.tls_insecure = value

    def username_pw_set(self, username: str, password: str) -> None:
        self.username = (username, password)

    def connect_async(self, host: str, port: int, keepalive: int) -> None:
        self.connected = (host, port, keepalive)

    def loop_start(self) -> None:
        self.running = True

    def loop_stop(self) -> None:
        self.running = False

    def disconnect(self) -> None:
        return None

    def subscribe(self, topic: str, qos: int) -> None:
        self.subscriptions.append((topic, qos))

    def publish(self, topic: str, payload: str, qos: int, retain: bool) -> None:
        self.published.append((topic, payload, qos, retain))


@pytest.fixture
def tls_material(tmp_path: Path) -> tuple[Path, Path, Path]:
    issuer_dir = tmp_path / "issuer"
    gateway_dir = tmp_path / "gateway"
    ca_cert = issuer_dir / "test-ca.crt"
    ca_key = issuer_dir / "test-ca.key"
    gateway_key = gateway_dir / "gateway.key"
    gateway_csr = gateway_dir / "gateway.csr"
    gateway_cert = gateway_dir / "gateway.crt"
    environment = {**os.environ, "TEST_TRANSPORT_CA_PASSWORD": "transport-test-password"}

    def run(script: str, *arguments: str) -> None:
        issuer_commands = {"create_project_ca.py": "create", "sign_gateway_csr.py": "sign"}
        command = (
            [sys.executable, "-m", "signing_admin.cli", issuer_commands[script], *arguments]
            if script in issuer_commands
            else [sys.executable, str(GATEWAY_SCRIPTS / script), *arguments]
        )
        subprocess.run(
            command, check=True, capture_output=True, text=True, env=environment,
            cwd=SIGNING_ADMIN_ROOT if script in issuer_commands else GATEWAY_SCRIPTS.parent,
        )

    run("create_project_ca.py", "--cert", str(ca_cert), "--key", str(ca_key),
        "--key-password-env", "TEST_TRANSPORT_CA_PASSWORD")
    run("generate_gateway_csr.py", "--ip", "127.0.0.1", "--key", str(gateway_key),
        "--csr", str(gateway_csr))
    run("sign_gateway_csr.py", "--csr", str(gateway_csr), "--ca-cert", str(ca_cert),
        "--ca-key", str(ca_key), "--ca-key-password-env", "TEST_TRANSPORT_CA_PASSWORD",
        "--output", str(gateway_cert))
    return ca_cert, gateway_cert, gateway_key


def mqtt_config(tls_material: tuple[Path, Path, Path]) -> GatewayConfig:
    ca_cert, gateway_cert, gateway_key = tls_material
    return GatewayConfig(
        mqtt_enabled=True,
        mqtt_host="broker.example.test",
        mqtt_ca=ca_cert,
        mqtt_client_cert=gateway_cert,
        mqtt_client_key=gateway_key,
        mqtt_topic_prefix="devcontrol/v1",
        enable_background_tasks=False,
    )


def test_mqtt_configuration_requires_tls_client_authentication(
    tls_material: tuple[Path, Path, Path],
) -> None:
    config = mqtt_config(tls_material)
    config.mqtt_client_cert = None
    config.mqtt_client_key = None
    with pytest.raises(ValueError, match="mTLS"):
        config.validate()


def test_mqtt5_tls_bridge_reuses_secure_command_pipeline(
    tmp_path: Path, tls_material: tuple[Path, Path, Path]
) -> None:
    gateway = GatewayService(
        GatewayConfig(
            database=tmp_path / "mqtt.db",
            initial_pairing_code="123456",
            enable_background_tasks=False,
        )
    )
    paired = gateway.sessions.pair("127.0.0.1", "mqtt-test-client", "123456")
    session = gateway.sessions.authenticate(paired.credential)
    light = gateway.devices.get("light-living-01")
    header: dict[str, object] = {
        "protocolVersion": PROTOCOL_VERSION,
        "messageId": "mqtt-command-message-0001",
        "deviceId": light["id"],
        "timestamp": now_ms(),
        "type": "command.request",
        "action": "setPower",
        "expectedStateVersion": light["stateVersion"],
    }
    envelope = SecureCommandEnvelope(
        **header,
        **encrypt_payload(session.data_key, {"power": True}, header),
    )
    wrapper = json.dumps(
        {
            "protocolVersion": PROTOCOL_VERSION,
            "credential": paired.credential,
            "command": envelope.model_dump(),
        },
        separators=(",", ":"),
    ).encode()
    fake = FakeMqttClient()
    bridge = MqttBridge(mqtt_config(tls_material), gateway, client=fake)

    async def exercise() -> None:
        await bridge.start()
        fake.on_connect(fake, None, None, 0, None)
        await bridge.handle_message(wrapper)
        published_before_invalid = len(fake.published)
        await bridge.handle_message(
            json.dumps(
                {
                    "protocolVersion": PROTOCOL_VERSION,
                    "credential": "invalid",
                    "command": envelope.model_dump(),
                }
            ).encode()
        )
        assert len(fake.published) == published_before_invalid
        await bridge.stop()
        await gateway.stop()

    asyncio.run(exercise())

    assert fake.connected == ("broker.example.test", 8883, 60)
    assert fake.tls_context is not None
    assert fake.tls_context.minimum_version == ssl.TLSVersion.TLSv1_2
    assert fake.tls_context.verify_mode == ssl.CERT_REQUIRED
    assert fake.tls_context.check_hostname is True
    assert fake.tls_insecure is False
    assert ("devcontrol/v1/commands", 1) in fake.subscriptions
    assert gateway.devices.get("light-living-01")["power"] is True
    result_messages = [item for item in fake.published if item[0].endswith("/results")]
    assert len(result_messages) == 1
    assert json.loads(result_messages[0][1])["success"] is True
    assert all(paired.credential not in item[1] for item in fake.published)
    assert any(
        item[0].endswith("/devices/light-living-01/state") and item[3]
        for item in fake.published
    )


def test_https_server_context_rejects_legacy_tls(
    tls_material: tuple[Path, Path, Path],
) -> None:
    _, gateway_cert, gateway_key = tls_material
    config = GatewayConfig(
        tls_cert=gateway_cert,
        tls_key=gateway_key,
    )
    server_config = _business_server_config(FastAPI(), config)
    assert server_config.ssl is not None
    assert server_config.ssl.minimum_version == ssl.TLSVersion.TLSv1_2
    cipher_names = {item["name"] for item in server_config.ssl.get_ciphers()}
    assert not any("RC4" in name or "3DES" in name for name in cipher_names)


def test_chunked_http_body_cannot_bypass_transport_size_limit(tmp_path: Path) -> None:
    app = create_app(
        GatewayConfig(
            database=tmp_path / "chunked-body.db",
            max_transport_message_bytes=16,
            enable_background_tasks=False,
        )
    )

    async def exercise() -> list[dict[str, Any]]:
        chunks = [
            {"type": "http.request", "body": b"x" * 10, "more_body": True},
            {"type": "http.request", "body": b"x" * 10, "more_body": False},
        ]
        sent: list[dict[str, Any]] = []

        async def receive() -> dict[str, Any]:
            return chunks.pop(0)

        async def send(message: dict[str, Any]) -> None:
            sent.append(message)

        await app(
            {
                "type": "http",
                "asgi": {"version": "3.0"},
                "http_version": "1.1",
                "method": "POST",
                "scheme": "https",
                "path": "/api/v1/commands",
                "raw_path": b"/api/v1/commands",
                "query_string": b"",
                "headers": [(b"content-type", b"application/json")],
                "client": ("127.0.0.1", 12345),
                "server": ("testserver", 443),
            },
            receive,
            send,
        )
        return sent

    response = asyncio.run(exercise())
    assert response[0]["type"] == "http.response.start"
    assert response[0]["status"] == 413
