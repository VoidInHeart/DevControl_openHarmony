from __future__ import annotations

import base64
import json
import tempfile
import unittest
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from fastapi.testclient import TestClient

from devcontrol_gateway.api import create_app
from devcontrol_gateway.config import GatewayConfig


class GatewayApiTest(unittest.TestCase):
    def test_pairing_and_authenticated_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = GatewayConfig(
                host="127.0.0.1",
                port=8443,
                database_path=root / "gateway.db",
                certificate_path=root / "gateway.crt",
                private_key_path=root / "gateway.key",
            )
            app = create_app(config)
            pairing_code = app.state.credentials.pairing_code
            with TestClient(app) as client:
                health = client.get("/api/v1/health")
                self.assertEqual(200, health.status_code)
                self.assertEqual("1.0", health.json()["protocolVersion"])

                pair = client.post(
                    "/api/v1/pair",
                    json={"pairingCode": pairing_code, "clientId": "test-client"},
                )
                self.assertEqual(200, pair.status_code)
                credential = pair.json()["credential"]
                data_key = base64.b64decode(pair.json()["dataKey"])
                self.assertEqual(401, client.get("/api/v1/devices").status_code)

                snapshot = client.get(
                    "/api/v1/devices", headers={"Authorization": f"Bearer {credential}"}
                )
                self.assertEqual(200, snapshot.status_code)
                self.assertEqual(4, len(snapshot.json()["devices"]))
                light = snapshot.json()["devices"][0]

                with client.websocket_connect(
                    "/ws/v1/events", headers={"Authorization": f"Bearer {credential}"}
                ) as socket:
                    initial = socket.receive_json()
                    self.assertEqual("snapshot", initial["type"])
                    timestamp = initial["timestamp"]
                    aad = (
                        f"1.0|api-message-1|{light['id']}|{timestamp}|"
                        f"command.request|turnOn|{light['stateVersion']}"
                    ).encode("utf-8")
                    encrypted = AESGCM(data_key).encrypt(
                        bytes.fromhex("abcdef0123456789abcdef01"), b"{}", aad
                    )
                    socket.send_json(
                        {
                            "protocolVersion": "1.0",
                            "messageId": "api-message-1",
                            "deviceId": light["id"],
                            "timestamp": timestamp,
                            "nonce": "abcdef0123456789abcdef01",
                            "type": "command.request",
                            "action": "turnOn",
                            "expectedStateVersion": light["stateVersion"],
                            "securePayload": {
                                "algorithm": "AES-256-GCM",
                                "ciphertext": base64.b64encode(encrypted[:-16]).decode("ascii"),
                                "authTag": base64.b64encode(encrypted[-16:]).decode("ascii"),
                            },
                        }
                    )
                    result = socket.receive_json()
                    changed = socket.receive_json()
                    self.assertTrue(result["success"])
                    self.assertEqual("state.changed", changed["type"])
                    self.assertTrue(changed["device"]["state"]["power"])


if __name__ == "__main__":
    unittest.main()
