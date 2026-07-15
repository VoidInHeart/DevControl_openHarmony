from __future__ import annotations

import copy
import base64
import json
import math
import random
import time
from collections import OrderedDict
from typing import Any

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .adapters import adapter_for
from .models import ClientSession, CommandOutcome, Device
from .repository import GatewayRepository


class GatewayService:
    def __init__(self, repository: GatewayRepository) -> None:
        self.repository = repository
        self.devices = self._default_devices()
        self._command_cache: OrderedDict[str, tuple[int, dict[str, Any]]] = OrderedDict()
        self._seen_nonces: dict[str, int] = {}
        self._tick_count = 0
        self._last_presence_at: dict[str, int] = {}

    def snapshot(self) -> list[dict[str, Any]]:
        return [copy.deepcopy(device.as_dict()) for device in self.devices.values()]

    def process_command(self, message: dict[str, Any], session: ClientSession) -> CommandOutcome:
        now = self._now_ms()
        message_id = str(message.get("messageId", ""))
        device_id = str(message.get("deviceId", ""))
        action = str(message.get("action", ""))
        nonce = str(message.get("nonce", ""))
        try:
            timestamp = int(message.get("timestamp", 0) or 0)
        except (TypeError, ValueError):
            timestamp = 0

        cached = self._command_cache.get(message_id)
        if cached is not None and cached[0] >= now:
            return CommandOutcome(copy.deepcopy(cached[1]))

        validation_error = self._validate_header(message, message_id, nonce, timestamp, now)
        if not validation_error and nonce in self._seen_nonces:
            validation_error = "REPLAY_DETECTED"
        if validation_error:
            return self._failure(message_id, device_id, action, validation_error, session, now)
        self._seen_nonces[nonce] = now + 300_000

        try:
            message = copy.deepcopy(message)
            message["payload"] = self._decrypt_payload(message, session)
        except (InvalidTag, ValueError, TypeError, KeyError, json.JSONDecodeError):
            outcome = self._failure(
                message_id,
                device_id,
                action,
                "INVALID_COMMAND",
                session,
                now,
                "PAYLOAD_AUTHENTICATION_FAILED",
            )
            self._command_cache[message_id] = (now + 300_000, copy.deepcopy(outcome.result))
            self.repository.append_log(
                timestamp_ms=now,
                category="security",
                device_id=device_id,
                client_id=session.client_id,
                action=action,
                result="failed",
                reason="PAYLOAD_AUTHENTICATION_FAILED",
            )
            return outcome

        try:
            if device_id == "gateway" and action == "executeAway":
                outcome = self._execute_away(message_id, session, now)
            else:
                outcome = self._execute_device_command(message, session, now)
        except (TypeError, ValueError, KeyError) as error:
            outcome = self._failure(
                message_id, device_id, action, "INVALID_COMMAND", session, now, str(error)
            )

        self._command_cache[message_id] = (now + 300_000, copy.deepcopy(outcome.result))
        self._prune_security_windows(now)
        return outcome

    @staticmethod
    def _decrypt_payload(message: dict[str, Any], session: ClientSession) -> dict[str, Any]:
        secure_payload = message["securePayload"]
        if not isinstance(secure_payload, dict) or secure_payload.get("algorithm") != "AES-256-GCM":
            raise ValueError("secure payload is required")
        nonce = bytes.fromhex(str(message["nonce"]))
        if len(nonce) != 12:
            raise ValueError("nonce must be 96 bits")
        ciphertext = base64.b64decode(str(secure_payload["ciphertext"]), validate=True)
        auth_tag = base64.b64decode(str(secure_payload["authTag"]), validate=True)
        if len(auth_tag) != 16:
            raise ValueError("auth tag must be 128 bits")
        expected_version = int(message.get("expectedStateVersion", -1))
        aad = (
            f"1.0|{message['messageId']}|{message['deviceId']}|{message['timestamp']}|"
            f"command.request|{message['action']}|{expected_version}"
        ).encode("utf-8")
        plaintext = AESGCM(session.data_key).decrypt(nonce, ciphertext + auth_tag, aad)
        payload = json.loads(plaintext.decode("utf-8"))
        if not isinstance(payload, dict):
            raise TypeError("decrypted payload must be an object")
        return payload

    def tick(self) -> list[Device]:
        now = self._now_ms()
        self._tick_count += 1
        changed: list[Device] = []
        environment = self.devices["env-living-01"]
        ac = self.devices["ac-living-01"]
        door = self.devices["door-entry-01"]
        light = self.devices["light-living-01"]

        base_temperature = 22.0 + 2.0 * math.sin(self._tick_count * 0.08) + random.uniform(-0.15, 0.15)
        base_humidity = 55.0 + 6.0 * math.sin(self._tick_count * 0.06 + 1.2) + random.uniform(-0.5, 0.5)
        if ac.state["power"]:
            target = float(ac.state["targetTemperatureCelsius"])
            current = float(environment.state["temperatureCelsius"])
            mode = ac.state["mode"]
            if mode == "cool" and current > target:
                base_temperature = current - min(0.2, current - target)
            elif mode == "heat" and current < target:
                base_temperature = current + min(0.2, target - current)
            elif mode == "dry":
                current_humidity = float(environment.state["humidityPercent"])
                base_humidity = current_humidity + max(-0.5, min(0.5, 50.0 - current_humidity))
            ac.state["running"] = True
        else:
            ac.state["running"] = False

        environment.state["temperatureCelsius"] = round(base_temperature, 1)
        environment.state["humidityPercent"] = round(max(0.0, min(100.0, base_humidity)), 0)
        self._touch(environment, now)
        changed.append(environment)

        if environment.state["presence"]:
            self._last_presence_at[environment.room_id] = now
        if light.state["automationEnabled"] and now >= int(light.state.get("manualOverrideUntil") or 0):
            threshold = int(light.state.get("illuminanceThresholdLux", 100))
            delay_ms = int(light.state.get("noPresenceDelaySeconds", 60)) * 1000
            should_turn_on = bool(environment.state["presence"]) and int(environment.state["illuminanceLux"]) < threshold
            last_presence = self._last_presence_at.get(environment.room_id, now)
            should_turn_off = not environment.state["presence"] and now - last_presence >= delay_ms
            if should_turn_on and not light.state["power"]:
                light.state["power"] = True
                light.state["brightness"] = max(int(light.state.get("lastNonZeroBrightness", 100)), 1)
                self._touch(light, now)
                changed.append(light)
            elif should_turn_off and light.state["power"]:
                light.state["lastNonZeroBrightness"] = max(int(light.state["brightness"]), 1)
                light.state["power"] = False
                self._touch(light, now)
                changed.append(light)

        auto_lock_at = door.state.get("autoLockAt")
        if door.state["status"] == "unlocked" and isinstance(auto_lock_at, int) and auto_lock_at <= now:
            door.state["status"] = "locked"
            door.state["autoLockAt"] = None
            self._touch(door, now)
            changed.append(door)
            self.repository.append_log(
                timestamp_ms=now,
                category="door",
                device_id=door.id,
                client_id="gateway",
                action="autoLock",
                result="success",
            )
        return changed

    def _execute_device_command(
        self, message: dict[str, Any], session: ClientSession, now: int
    ) -> CommandOutcome:
        device_id = str(message["deviceId"])
        action = str(message["action"])
        message_id = str(message["messageId"])
        device = self.devices.get(device_id)
        if device is None:
            return self._failure(message_id, device_id, action, "INVALID_COMMAND", session, now)
        if not device.online:
            return self._failure(message_id, device_id, action, "DEVICE_OFFLINE", session, now)
        expected = message.get("expectedStateVersion")
        if expected is not None and int(expected) != device.state_version:
            return self._failure(message_id, device_id, action, "STATE_CONFLICT", session, now)
        payload = message.get("payload")
        if not isinstance(payload, dict):
            raise TypeError("payload must be an object")

        if device.type == "light":
            self._apply_light(device, action, payload, now)
        elif device.type == "airConditioner":
            encoded = adapter_for(device.brand).encode(action, payload, device.state)
            self._apply_ac(device, action, payload)
            self.repository.append_log(
                timestamp_ms=now,
                category="adapter",
                device_id=device.id,
                client_id=session.client_id,
                action=action,
                result="success",
                detail={"brand": device.brand, "encodedCommand": encoded},
            )
        elif device.type == "doorLock":
            self._apply_door(device, action, now)
        else:
            raise ValueError("environment devices are read-only")

        self._touch(device, now)
        result = self._success(message_id, device.id, action, device.state_version, now)
        self.repository.append_log(
            timestamp_ms=now,
            category="command",
            device_id=device.id,
            client_id=session.client_id,
            action=action,
            result="success",
        )
        return CommandOutcome(result, [device])

    def _execute_away(self, message_id: str, session: ClientSession, now: int) -> CommandOutcome:
        changed: list[Device] = []
        for device in self.devices.values():
            if device.type == "light":
                device.state["power"] = False
            elif device.type == "airConditioner":
                device.state["power"] = False
                device.state["running"] = False
            elif device.type == "doorLock":
                device.state["status"] = "locked"
                device.state["autoLockAt"] = None
            else:
                continue
            self._touch(device, now)
            changed.append(device)
        result = self._success(message_id, "gateway", "executeAway", 0, now)
        self.repository.append_log(
            timestamp_ms=now,
            category="scene",
            device_id="gateway",
            client_id=session.client_id,
            action="executeAway",
            result="success",
            detail={"devices": [device.id for device in changed]},
        )
        return CommandOutcome(result, changed)

    def _apply_light(self, device: Device, action: str, payload: dict[str, Any], now: int) -> None:
        if action == "turnOn":
            device.state["power"] = True
            device.state["brightness"] = max(int(device.state.get("lastNonZeroBrightness", 100)), 1)
            device.state["manualOverrideUntil"] = now + 300_000
        elif action == "turnOff":
            current = int(device.state.get("brightness", 100))
            device.state["lastNonZeroBrightness"] = max(current, 1)
            device.state["power"] = False
            device.state["manualOverrideUntil"] = now + 300_000
        elif action == "setBrightness":
            brightness = int(payload["brightness"])
            if brightness < 0 or brightness > 100:
                raise ValueError("brightness must be 0..100")
            device.state["brightness"] = brightness
            device.state["power"] = brightness > 0
            if brightness > 0:
                device.state["lastNonZeroBrightness"] = brightness
            device.state["manualOverrideUntil"] = now + 300_000
        elif action == "setAutomation":
            threshold = int(payload["illuminanceThresholdLux"])
            delay = int(payload["noPresenceDelaySeconds"])
            if threshold < 10 or threshold > 500 or delay < 5 or delay > 600:
                raise ValueError("automation parameters are outside the accepted range")
            device.state["automationEnabled"] = bool(payload["enabled"])
            device.state["illuminanceThresholdLux"] = threshold
            device.state["noPresenceDelaySeconds"] = delay
            if device.state["automationEnabled"]:
                device.state["manualOverrideUntil"] = None
        else:
            raise ValueError("unsupported light command")

    @staticmethod
    def _apply_ac(device: Device, action: str, payload: dict[str, Any]) -> None:
        if action == "acPowerOn":
            device.state["power"] = True
        elif action == "acPowerOff":
            device.state["power"] = False
            device.state["running"] = False
        elif action == "setTargetTemp":
            target = int(payload["temperatureCelsius"])
            if target < 16 or target > 30:
                raise ValueError("target temperature must be 16..30")
            device.state["targetTemperatureCelsius"] = target
        elif action == "setACMode":
            mode = str(payload["mode"])
            if mode not in {"auto", "cool", "heat", "dry", "fan"}:
                raise ValueError("unsupported air conditioner mode")
            device.state["mode"] = mode
        else:
            raise ValueError("unsupported air conditioner command")

    @staticmethod
    def _apply_door(device: Device, action: str, now: int) -> None:
        if action == "lock":
            device.state["status"] = "locked"
            device.state["autoLockAt"] = None
        elif action == "unlock":
            device.state["status"] = "unlocked"
            device.state["autoLockAt"] = now + 10_000
        else:
            raise ValueError("unsupported door command")

    def _failure(
        self,
        message_id: str,
        device_id: str,
        action: str,
        error_code: str,
        session: ClientSession,
        now: int,
        detail: str = "",
    ) -> CommandOutcome:
        result = {
            "protocolVersion": "1.0",
            "messageId": message_id or self._event_id(),
            "deviceId": device_id,
            "timestamp": now,
            "type": "command.result",
            "action": action,
            "success": False,
            "errorCode": error_code,
            "errorMessage": detail or error_code,
        }
        self.repository.append_log(
            timestamp_ms=now,
            category="command",
            device_id=device_id,
            client_id=session.client_id,
            action=action,
            result="failed",
            reason=error_code,
        )
        return CommandOutcome(result)

    @staticmethod
    def _success(message_id: str, device_id: str, action: str, state_version: int, now: int) -> dict[str, Any]:
        return {
            "protocolVersion": "1.0",
            "messageId": message_id,
            "deviceId": device_id,
            "timestamp": now,
            "type": "command.result",
            "action": action,
            "success": True,
            "stateVersion": state_version,
        }

    @staticmethod
    def _validate_header(
        message: dict[str, Any], message_id: str, nonce: str, timestamp: int, now: int
    ) -> str:
        if message.get("protocolVersion") != "1.0" or message.get("type") != "command.request":
            return "INVALID_COMMAND"
        if not message_id or len(message_id) > 128 or not nonce or len(nonce) != 24:
            return "INVALID_COMMAND"
        if abs(now - timestamp) > 30_000:
            return "REPLAY_DETECTED"
        return ""

    def _prune_security_windows(self, now: int) -> None:
        while self._command_cache:
            first_key = next(iter(self._command_cache))
            if self._command_cache[first_key][0] >= now:
                break
            self._command_cache.popitem(last=False)
        expired_nonces = [nonce for nonce, expires_at in self._seen_nonces.items() if expires_at < now]
        for nonce in expired_nonces:
            self._seen_nonces.pop(nonce, None)

    def _touch(self, device: Device, now: int) -> None:
        device.state_version += 1
        device.updated_at = now

    @staticmethod
    def _now_ms() -> int:
        return int(time.time() * 1000)

    @staticmethod
    def _event_id() -> str:
        return f"gw-{time.time_ns():x}-{random.getrandbits(32):08x}"

    @classmethod
    def state_event(cls, device: Device) -> dict[str, Any]:
        return {
            "protocolVersion": "1.0",
            "messageId": cls._event_id(),
            "deviceId": device.id,
            "timestamp": cls._now_ms(),
            "type": "state.changed",
            "stateVersion": device.state_version,
            "device": copy.deepcopy(device.as_dict()),
        }

    @classmethod
    def heartbeat_event(cls) -> dict[str, Any]:
        return {
            "protocolVersion": "1.0",
            "messageId": cls._event_id(),
            "deviceId": "gateway",
            "timestamp": cls._now_ms(),
            "type": "heartbeat",
        }

    @classmethod
    def snapshot_event(cls, devices: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "protocolVersion": "1.0",
            "messageId": cls._event_id(),
            "deviceId": "gateway",
            "timestamp": cls._now_ms(),
            "type": "snapshot",
            "devices": devices,
        }

    @staticmethod
    def _default_devices() -> dict[str, Device]:
        now = int(time.time() * 1000)
        return {
            "light-living-01": Device(
                "light-living-01",
                "客厅主灯",
                "living-room",
                "light",
                {
                    "power": False,
                    "brightness": 0,
                    "lastNonZeroBrightness": 100,
                    "automationEnabled": False,
                    "illuminanceThresholdLux": 100,
                    "noPresenceDelaySeconds": 60,
                    "manualOverrideUntil": None,
                },
                updated_at=now,
            ),
            "env-living-01": Device(
                "env-living-01",
                "客厅环境传感器",
                "living-room",
                "environment",
                {
                    "temperatureCelsius": 22.0,
                    "humidityPercent": 55.0,
                    "presence": True,
                    "illuminanceLux": 80,
                },
                updated_at=now,
            ),
            "ac-living-01": Device(
                "ac-living-01",
                "客厅空调",
                "living-room",
                "airConditioner",
                {
                    "power": False,
                    "mode": "auto",
                    "targetTemperatureCelsius": 26,
                    "running": False,
                },
                brand="haierSim",
                updated_at=now,
            ),
            "door-entry-01": Device(
                "door-entry-01",
                "入户门锁",
                "entry",
                "doorLock",
                {"status": "locked", "batteryPercent": 100, "autoLockAt": None},
                updated_at=now,
            ),
        }
