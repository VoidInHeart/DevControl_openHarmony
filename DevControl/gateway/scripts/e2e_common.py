from __future__ import annotations

import json
import secrets
import ssl
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import httpx
import websocket

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from devcontrol_gateway.models import PROTOCOL_VERSION
from devcontrol_gateway.security import base64url_decode, encrypt_payload, now_ms


def pair(
    base_url: str, ca_file: Path, pairing_code: str
) -> tuple[str, bytes, list[dict[str, object]]]:
    with httpx.Client(verify=str(ca_file), timeout=5) as client:
        health = client.get(base_url + "/api/v1/health")
        health.raise_for_status()
        response = client.post(
            base_url + "/api/v1/pair",
            json={
                "protocolVersion": PROTOCOL_VERSION,
                "pairingCode": pairing_code,
                "clientId": "e2e-" + secrets.token_hex(12),
            },
        )
        response.raise_for_status()
        paired = response.json()
        headers = {"Authorization": "Bearer " + paired["credential"]}
        snapshot = client.get(base_url + "/api/v1/devices", headers=headers)
        snapshot.raise_for_status()
    return (
        paired["credential"],
        base64url_decode(paired["dataKey"]),
        snapshot.json()["devices"],
    )


def connect_websocket(
    base_url: str, ca_file: Path, credential: str
) -> websocket.WebSocket:
    parsed = urlparse(base_url)
    ws_url = f"wss://{parsed.netloc}/ws/v1/events"
    return websocket.create_connection(
        ws_url,
        timeout=5,
        header=[f"Authorization: Bearer {credential}"],
        sslopt={
            "cert_reqs": ssl.CERT_REQUIRED,
            "ca_certs": str(ca_file),
            "check_hostname": True,
        },
    )


def make_command(
    data_key: bytes,
    device_id: str,
    action: str,
    expected_version: int | None,
    payload: dict[str, object],
    message_id: str | None = None,
) -> dict[str, object]:
    header: dict[str, object] = {
        "protocolVersion": PROTOCOL_VERSION,
        "messageId": message_id or secrets.token_urlsafe(16).rstrip("="),
        "deviceId": device_id,
        "timestamp": now_ms(),
        "type": "command.request",
        "action": action,
        "expectedStateVersion": expected_version,
    }
    return {**header, **encrypt_payload(data_key, payload, header)}


def receive_command_cycle(
    socket: websocket.WebSocket,
    message_id: str,
    device_id: str,
    require_state: bool = True,
) -> tuple[dict[str, object], dict[str, object] | None, float, float | None]:
    started = time.perf_counter()
    result: dict[str, object] | None = None
    state: dict[str, object] | None = None
    result_latency: float | None = None
    state_latency: float | None = None
    while result is None or (
        require_state and result.get("success") and state is None
    ):
        message = json.loads(socket.recv())
        message_type = message.get("type")
        if (
            message_type == "command.result"
            and message.get("messageId") == message_id
        ):
            result = message
            result_latency = time.perf_counter() - started
            if not result.get("success"):
                break
        elif (
            message_type == "state.changed"
            and message.get("deviceId") == device_id
        ):
            state = message
            state_latency = time.perf_counter() - started
    assert result is not None and result_latency is not None
    return result, state, result_latency, state_latency
