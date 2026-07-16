from __future__ import annotations

import copy
import math
import random
import time
from datetime import UTC, datetime
from typing import Any

from .adapters import ADAPTERS, NormalizedAcCommand, get_adapter
from .errors import (
    COMMAND_TIMEOUT,
    DEVICE_OFFLINE,
    INTERNAL_ERROR,
    INVALID_COMMAND,
    STATE_CONFLICT,
    GatewayError,
)
from .security import now_ms
from .storage import GatewayStorage


def iso_now() -> str:
    return datetime.now(UTC).isoformat()


class DeviceRegistry:
    def __init__(self, storage: GatewayStorage) -> None:
        self.storage = storage
        self._pending_alerts: list[dict[str, Any]] = []
        self.devices: dict[str, dict[str, Any]] = self._default_devices()

    @staticmethod
    def _base(
        device_id: str, name: str, room_id: str, device_type: str
    ) -> dict[str, Any]:
        return {
            "id": device_id,
            "name": name,
            "roomId": room_id,
            "type": device_type,
            "online": True,
            "stateVersion": 1,
            "updatedAt": iso_now(),
            "_commandDelayMs": 0,
            "_failNextCommand": False,
        }

    def _default_devices(self) -> dict[str, dict[str, Any]]:
        light = self._base(
            "light-living-01", "客厅主灯", "living", "light"
        )
        light.update(
            {
                "power": False,
                "brightness": 60,
                "lastNonZeroBrightness": 60,
                "automation": {
                    "enabled": False,
                    "illuminanceThresholdLux": 100,
                    "noPresenceDelaySeconds": 60,
                    "manualOverrideUntil": None,
                },
                "_noPresenceSince": None,
            }
        )

        environment = self._base(
            "env-living-01", "客厅环境传感器", "living", "environment"
        )
        environment.update(
            {
                "temperatureCelsius": 24.0,
                "humidityPercent": 55.0,
                "illuminanceLux": 80.0,
                "presence": True,
                "dataValid": True,
                "_manualInjectionUntil": 0.0,
            }
        )

        ac = self._base(
            "ac-living-01", "客厅空调", "living", "airConditioner"
        )
        ac.update(
            {
                "brand": "haierSim",
                "power": False,
                "mode": "auto",
                "targetTemperatureCelsius": 24,
                "running": False,
                "lastAdapterFrame": "",
            }
        )

        door = self._base(
            "door-entry-01", "入户门锁", "entry", "doorLock"
        )
        door.update(
            {
                "locked": True,
                "jammed": False,
                "batteryPercent": 92,
                "autoLockEnabled": True,
                "autoLockDelaySeconds": 10,
                "autoLockAt": None,
            }
        )
        return {device["id"]: device for device in (light, environment, ac, door)}

    def snapshot(self) -> list[dict[str, Any]]:
        return [self.public_device(device) for device in self.devices.values()]

    @staticmethod
    def public_device(device: dict[str, Any]) -> dict[str, Any]:
        return copy.deepcopy(
            {key: value for key, value in device.items() if not key.startswith("_")}
        )

    def get(self, device_id: str) -> dict[str, Any]:
        device = self.devices.get(device_id)
        if device is None:
            raise GatewayError(INVALID_COMMAND, "目标设备不存在")
        return device

    def _ensure_commandable(
        self, device: dict[str, Any], expected_version: int | None
    ) -> None:
        if not device["online"]:
            raise GatewayError(DEVICE_OFFLINE, "目标设备当前离线")
        if (
            expected_version is not None
            and expected_version != device["stateVersion"]
        ):
            raise GatewayError(STATE_CONFLICT, "设备状态版本已更新，请刷新后重试")
        delay_ms = int(device.get("_commandDelayMs", 0))
        if delay_ms > 5_000:
            raise GatewayError(COMMAND_TIMEOUT, "设备响应超过5秒超时限制")
        if delay_ms > 0:
            time.sleep(delay_ms / 1000)
        if device.get("_failNextCommand", False):
            device["_failNextCommand"] = False
            raise GatewayError(INTERNAL_ERROR, "设备模拟器注入了一次命令故障")

    @staticmethod
    def _touch(device: dict[str, Any]) -> None:
        device["stateVersion"] += 1
        device["updatedAt"] = iso_now()

    def execute(
        self,
        device_id: str,
        action: str,
        payload: dict[str, object],
        expected_version: int | None,
    ) -> tuple[dict[str, Any] | None, list[dict[str, object]] | None]:
        if device_id == "scene-away":
            if action != "executeAway":
                raise GatewayError(INVALID_COMMAND, "场景动作不受支持")
            return None, self._execute_away()

        device = self.get(device_id)
        self._ensure_commandable(device, expected_version)
        device_type = device["type"]
        if device_type == "light":
            self._execute_light(device, action, payload)
        elif device_type == "airConditioner":
            self._execute_ac(device, action, payload)
        elif device_type == "doorLock":
            self._execute_door(device, action, payload)
        else:
            raise GatewayError(INVALID_COMMAND, "该设备不接受控制命令")
        return self.public_device(device), None

    def _execute_light(
        self, device: dict[str, Any], action: str, payload: dict[str, object]
    ) -> None:
        now = time.time()
        if action == "setPower":
            power = payload.get("power")
            if not isinstance(power, bool):
                raise GatewayError(INVALID_COMMAND, "灯光电源参数必须为布尔值")
            device["power"] = power
            if power and device["brightness"] == 0:
                device["brightness"] = max(1, device["lastNonZeroBrightness"])
            device["automation"]["manualOverrideUntil"] = int((now + 300) * 1000)
        elif action == "setBrightness":
            brightness = payload.get("brightness")
            if (
                isinstance(brightness, bool)
                or not isinstance(brightness, (int, float))
                or brightness < 0
                or brightness > 100
            ):
                raise GatewayError(INVALID_COMMAND, "亮度必须在0到100之间")
            value = int(brightness)
            device["brightness"] = value
            device["power"] = value > 0
            if value > 0:
                device["lastNonZeroBrightness"] = value
            device["automation"]["manualOverrideUntil"] = int((now + 300) * 1000)
        elif action == "setAutomationConfig":
            enabled = payload.get("enabled")
            threshold = payload.get("illuminanceThresholdLux")
            delay = payload.get("noPresenceDelaySeconds")
            if not isinstance(enabled, bool):
                raise GatewayError(INVALID_COMMAND, "自动照明开关参数无效")
            if (
                isinstance(threshold, bool)
                or not isinstance(threshold, (int, float))
                or threshold < 10
                or threshold > 500
            ):
                raise GatewayError(INVALID_COMMAND, "照度阈值必须在10到500 lx之间")
            if (
                isinstance(delay, bool)
                or not isinstance(delay, (int, float))
                or delay < 5
                or delay > 600
            ):
                raise GatewayError(INVALID_COMMAND, "无人延时必须在5到600秒之间")
            device["automation"].update(
                {
                    "enabled": enabled,
                    "illuminanceThresholdLux": int(threshold),
                    "noPresenceDelaySeconds": int(delay),
                    "manualOverrideUntil": None,
                }
            )
            device["_noPresenceSince"] = None
        else:
            raise GatewayError(INVALID_COMMAND, "灯光动作不受支持")
        self._touch(device)

    def _execute_ac(
        self, device: dict[str, Any], action: str, payload: dict[str, object]
    ) -> None:
        if action == "setPower":
            power = payload.get("power")
            if not isinstance(power, bool):
                raise GatewayError(INVALID_COMMAND, "空调电源参数必须为布尔值")
            command = NormalizedAcCommand(action=action, power=power)
            device["power"] = power
            device["running"] = power
        elif action == "setMode":
            mode = payload.get("mode")
            if not isinstance(mode, str):
                raise GatewayError(INVALID_COMMAND, "空调模式参数无效")
            command = NormalizedAcCommand(action=action, mode=mode)
            device["mode"] = mode
        elif action == "setTemperature":
            temperature = payload.get("temperatureCelsius")
            if isinstance(temperature, bool) or not isinstance(temperature, int):
                raise GatewayError(INVALID_COMMAND, "目标温度必须为整数")
            command = NormalizedAcCommand(
                action=action, temperature=temperature
            )
            device["targetTemperatureCelsius"] = temperature
        elif action == "setBrand":
            brand = payload.get("brand")
            if not isinstance(brand, str) or brand not in ADAPTERS:
                raise GatewayError(INVALID_COMMAND, "模拟品牌不受支持")
            device["brand"] = brand
            command = NormalizedAcCommand(action="setPower", power=device["power"])
        else:
            raise GatewayError(INVALID_COMMAND, "空调动作不受支持")

        adapter = get_adapter(device["brand"])
        device["lastAdapterFrame"] = adapter.encode(command)
        self._touch(device)

    def _execute_door(
        self, device: dict[str, Any], action: str, payload: dict[str, object]
    ) -> None:
        if device["jammed"] and action in {"lock", "unlock"}:
            self._record_alert(
                device["id"],
                "critical",
                "DOOR_JAMMED",
                "门锁卡滞，操作被拒绝",
            )
            raise GatewayError(INTERNAL_ERROR, "门锁卡滞，无法完成操作")
        if action == "lock":
            device["locked"] = True
            device["autoLockAt"] = None
        elif action == "unlock":
            device["locked"] = False
            if device["autoLockEnabled"]:
                device["autoLockAt"] = int(
                    (time.time() + device["autoLockDelaySeconds"]) * 1000
                )
        elif action == "setAutoLockConfig":
            enabled = payload.get("enabled")
            delay = payload.get("delaySeconds")
            if not isinstance(enabled, bool):
                raise GatewayError(INVALID_COMMAND, "自动上锁开关参数无效")
            if (
                isinstance(delay, bool)
                or not isinstance(delay, int)
                or delay < 5
                or delay > 60
            ):
                raise GatewayError(INVALID_COMMAND, "自动上锁延时必须在5到60秒之间")
            device["autoLockEnabled"] = enabled
            device["autoLockDelaySeconds"] = delay
            if not enabled:
                device["autoLockAt"] = None
        else:
            raise GatewayError(INVALID_COMMAND, "门锁动作不受支持")
        self._touch(device)

    def _execute_away(self) -> list[dict[str, object]]:
        results: list[dict[str, object]] = []
        actions = (
            ("light-living-01", "setPower", {"power": False}),
            ("ac-living-01", "setPower", {"power": False}),
            ("door-entry-01", "lock", {}),
        )
        for device_id, action, payload in actions:
            try:
                device = self.get(device_id)
                self._ensure_commandable(device, device["stateVersion"])
                if device["type"] == "light":
                    self._execute_light(device, action, payload)
                elif device["type"] == "airConditioner":
                    self._execute_ac(device, action, payload)
                else:
                    self._execute_door(device, action, payload)
                results.append(
                    {"deviceId": device_id, "success": True, "errorCode": None}
                )
            except GatewayError as exc:
                results.append(
                    {
                        "deviceId": device_id,
                        "success": False,
                        "errorCode": exc.code,
                    }
                )
        return results

    def tick(self) -> list[dict[str, Any]]:
        changed: list[dict[str, Any]] = []
        env = self.devices["env-living-01"]
        ac = self.devices["ac-living-01"]
        light = self.devices["light-living-01"]
        door = self.devices["door-entry-01"]
        now = time.time()

        if env["online"] and now >= env["_manualInjectionUntil"]:
            phase = now / 180
            target_temp = 24.0 + math.sin(phase) * 0.4
            target_humidity = 55.0 + math.sin(phase / 2) * 1.5
            if ac["online"] and ac["power"]:
                mode = ac["mode"]
                if mode in {"cool", "heat", "auto"}:
                    target_temp = float(ac["targetTemperatureCelsius"])
                if mode == "dry":
                    target_humidity = 50.0
            old_temp = env["temperatureCelsius"]
            old_humidity = env["humidityPercent"]
            env["temperatureCelsius"] = round(
                old_temp + (target_temp - old_temp) * 0.08 + random.uniform(-0.02, 0.02),
                1,
            )
            env["humidityPercent"] = round(
                old_humidity
                + (target_humidity - old_humidity) * 0.06
                + random.uniform(-0.05, 0.05),
                1,
            )
            env["illuminanceLux"] = round(
                max(0.0, 120 + math.sin(now / 60) * 80), 1
            )
            self._touch(env)
            changed.append(self.public_device(env))

        if env["online"]:
            self.storage.record_environment(
                timestamp_ms=now_ms(),
                device_id=env["id"],
                temperature_celsius=env["temperatureCelsius"],
                humidity_percent=env["humidityPercent"],
                illuminance_lux=env["illuminanceLux"],
                presence=env["presence"],
            )

        if light["online"] and light["automation"]["enabled"]:
            override_until = light["automation"]["manualOverrideUntil"]
            if override_until is None or now_ms() >= override_until:
                should_touch = False
                if (
                    env["presence"]
                    and env["illuminanceLux"]
                    < light["automation"]["illuminanceThresholdLux"]
                ):
                    light["_noPresenceSince"] = None
                    if not light["power"]:
                        light["power"] = True
                        light["brightness"] = max(
                            1, light["lastNonZeroBrightness"]
                        )
                        should_touch = True
                elif not env["presence"]:
                    if light["_noPresenceSince"] is None:
                        light["_noPresenceSince"] = now
                    elif (
                        light["power"]
                        and now - light["_noPresenceSince"]
                        >= light["automation"]["noPresenceDelaySeconds"]
                    ):
                        light["power"] = False
                        should_touch = True
                if should_touch:
                    self._touch(light)
                    changed.append(self.public_device(light))

        auto_lock_at = door["autoLockAt"]
        if (
            door["online"]
            and not door["locked"]
            and door["autoLockEnabled"]
            and auto_lock_at is not None
            and now_ms() >= auto_lock_at
        ):
            door["locked"] = True
            door["autoLockAt"] = None
            self._touch(door)
            changed.append(self.public_device(door))
            self.storage.record_audit(
                timestamp_ms=now_ms(),
                client_id="gateway-rule",
                device_id=door["id"],
                action="autoLock",
                result="success",
                error_code=None,
                message_id="auto-lock",
            )

        if env["temperatureCelsius"] < -10 or env["temperatureCelsius"] > 45:
            env["dataValid"] = False
        elif env["humidityPercent"] < 0 or env["humidityPercent"] > 100:
            env["dataValid"] = False
        else:
            env["dataValid"] = True
        return changed

    def inject_fault(
        self, device_id: str, values: dict[str, object | None]
    ) -> dict[str, Any]:
        device = self.get(device_id)
        mapping = {
            "online": "online",
            "jammed": "jammed",
            "batteryPercent": "batteryPercent",
            "commandDelayMs": "_commandDelayMs",
            "failNextCommand": "_failNextCommand",
        }
        changed = False
        for source, target in mapping.items():
            value = values.get(source)
            if value is not None and target in device:
                device[target] = value
                changed = True
        if changed:
            self._touch(device)
            if device.get("batteryPercent", 100) <= 20:
                self._record_alert(
                    device_id,
                    "warning",
                    "LOW_BATTERY",
                    "门锁电量低于20%",
                )
        return self.public_device(device)

    def _record_alert(
        self,
        device_id: str,
        severity: str,
        code: str,
        description: str,
    ) -> None:
        timestamp = now_ms()
        self.storage.record_alert(
            timestamp_ms=timestamp,
            device_id=device_id,
            severity=severity,
            code=code,
            description=description,
        )
        self._pending_alerts.append(
            {
                "protocolVersion": "1.0",
                "type": "alert.raised",
                "timestamp": timestamp,
                "deviceId": device_id,
                "severity": severity,
                "code": code,
                "description": description,
            }
        )

    def drain_alerts(self) -> list[dict[str, Any]]:
        alerts = self._pending_alerts
        self._pending_alerts = []
        return alerts

    def inject_environment(
        self, values: dict[str, object | None]
    ) -> dict[str, Any]:
        env = self.devices["env-living-01"]
        for key in (
            "temperatureCelsius",
            "humidityPercent",
            "illuminanceLux",
            "presence",
        ):
            value = values.get(key)
            if value is not None:
                env[key] = value
        env["_manualInjectionUntil"] = time.time() + 30
        self._touch(env)
        return self.public_device(env)
