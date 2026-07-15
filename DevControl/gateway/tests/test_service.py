from __future__ import annotations

import base64
import json
import tempfile
import time
import unittest
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from devcontrol_gateway.models import ClientSession
from devcontrol_gateway.repository import GatewayRepository
from devcontrol_gateway.service import GatewayService


class GatewayServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.repository = GatewayRepository(Path(self.temp_directory.name) / "gateway.db")
        self.service = GatewayService(self.repository)
        self.session = ClientSession("test-client", "digest", bytes(32), int(time.time() * 1000) + 60_000)

    def tearDown(self) -> None:
        self.repository.close()
        self.temp_directory.cleanup()

    def command(
        self,
        message_id: str,
        device_id: str,
        action: str,
        payload: dict[str, object],
        state_version: int,
        nonce: str = "0123456789abcdef01234567",
    ) -> dict[str, object]:
        timestamp = int(time.time() * 1000)
        aad = (
            f"1.0|{message_id}|{device_id}|{timestamp}|command.request|{action}|{state_version}"
        ).encode("utf-8")
        encrypted = AESGCM(self.session.data_key).encrypt(
            bytes.fromhex(nonce), json.dumps(payload, separators=(",", ":")).encode("utf-8"), aad
        )
        return {
            "protocolVersion": "1.0",
            "messageId": message_id,
            "deviceId": device_id,
            "timestamp": timestamp,
            "nonce": nonce,
            "type": "command.request",
            "action": action,
            "expectedStateVersion": state_version,
            "securePayload": {
                "algorithm": "AES-256-GCM",
                "ciphertext": base64.b64encode(encrypted[:-16]).decode("ascii"),
                "authTag": base64.b64encode(encrypted[-16:]).decode("ascii"),
            },
        }

    def test_duplicate_message_id_is_idempotent(self) -> None:
        device = self.service.devices["light-living-01"]
        message = self.command("message-1", device.id, "turnOn", {}, device.state_version)
        first = self.service.process_command(message, self.session)
        version_after_first = device.state_version
        second = self.service.process_command(message, self.session)
        self.assertTrue(first.result["success"])
        self.assertEqual(first.result, second.result)
        self.assertEqual(version_after_first, device.state_version)

    def test_stale_state_version_is_rejected(self) -> None:
        device = self.service.devices["light-living-01"]
        message = self.command("message-2", device.id, "turnOn", {}, 0)
        outcome = self.service.process_command(message, self.session)
        self.assertFalse(outcome.result["success"])
        self.assertEqual("STATE_CONFLICT", outcome.result["errorCode"])

    def test_away_scene_returns_each_changed_device(self) -> None:
        message = self.command("message-3", "gateway", "executeAway", {}, -1)
        outcome = self.service.process_command(message, self.session)
        self.assertTrue(outcome.result["success"])
        self.assertEqual(3, len(outcome.changed_devices))
        self.assertFalse(self.service.devices["light-living-01"].state["power"])
        self.assertFalse(self.service.devices["ac-living-01"].state["power"])
        self.assertEqual("locked", self.service.devices["door-entry-01"].state["status"])

    def test_tampered_ciphertext_is_rejected(self) -> None:
        device = self.service.devices["light-living-01"]
        message = self.command("message-4", device.id, "turnOn", {}, device.state_version)
        message["securePayload"]["ciphertext"] = "AAAA"
        outcome = self.service.process_command(message, self.session)
        self.assertFalse(outcome.result["success"])
        self.assertEqual("PAYLOAD_AUTHENTICATION_FAILED", outcome.result["errorMessage"])
        self.assertFalse(device.state["power"])


if __name__ == "__main__":
    unittest.main()
