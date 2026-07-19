from __future__ import annotations

import math
import random
import time
from abc import ABC, abstractmethod
from datetime import UTC, datetime
from typing import Any, Protocol

from .adapters import ADAPTERS, NormalizedAcCommand, get_adapter
from .errors import INTERNAL_ERROR, INVALID_COMMAND, GatewayError
from .security import now_ms
from .storage import GatewayStorage


def iso_now() -> str:
    return datetime.now(UTC).isoformat()


def base_device(
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


class DriverContext(Protocol):
    storage: GatewayStorage

    def get(self, device_id: str) -> dict[str, Any]: ...

    def find_first(
        self, device_type: str, room_id: str | None = None
    ) -> dict[str, Any] | None: ...

    def record_alert(
        self,
        device_id: str,
        severity: str,
        code: str,
        description: str,
    ) -> None: ...


class DeviceDriver(ABC):
    """Explicit extension point for a device family.

    Drivers own device-specific state transitions and validation. The registry owns
    transport-neutral concerns such as state versions, online checks and injected
    failures.
    """

    device_type: str
    tick_priority: int = 100
    requires_category: bool = True

    def create_categories(self) -> list[dict[str, Any]]:
        """Declare generic UI categories before creating devices that use them."""
        return []

    @abstractmethod
    def create_devices(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    def execute(
        self,
        device: dict[str, Any],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
    ) -> None:
        raise GatewayError(INVALID_COMMAND, "该设备不接受控制命令")

    def attest_registration(
        self,
        device_id: str,
        name: str,
        room_id: str,
        category_id: str,
        capabilities: list[str],
    ) -> dict[str, Any]:
        raise GatewayError(INVALID_COMMAND, "该设备类型暂不支持二维码注册")

    def tick(self, device: dict[str, Any], context: DriverContext) -> bool:
        return False


class LightDriver(DeviceDriver):
    device_type = "light"
    tick_priority = 30

    def create_categories(self) -> list[dict[str, Any]]:
        return [
            {
                "id": "lighting",
                "title": "灯光",
                "icon": "○",
                "homeOnly": False,
            }
        ]

    def create_devices(self) -> list[dict[str, Any]]:
        return [
            self._light("light-living-01", "客厅主灯", "living", 60),
            self._light("light-master-01", "主卧顶灯", "masterBedroom", 60),
            self._light("light-bedroom-01", "次卧阅读灯", "bedroom", 50),
        ]

    def _light(
        self,
        device_id: str,
        name: str,
        room_id: str,
        brightness: int,
    ) -> dict[str, Any]:
        light = base_device(device_id, name, room_id, self.device_type)
        light.update(
            {
                "_categoryId": "lighting",
                "power": False,
                "brightness": brightness,
                "lastNonZeroBrightness": brightness,
                "automation": {
                    "enabled": False,
                    "illuminanceThresholdLux": 100,
                    "noPresenceDelaySeconds": 60,
                    "manualOverrideUntil": None,
                },
                "_noPresenceSince": None,
            }
        )
        return light

    def attest_registration(
        self,
        device_id: str,
        name: str,
        room_id: str,
        category_id: str,
        capabilities: list[str],
    ) -> dict[str, Any]:
        required_capabilities = {
            "setPower",
            "setBrightness",
            "setAutomationConfig",
        }
        if category_id != "lighting" or set(capabilities) != required_capabilities:
            raise GatewayError(
                INVALID_COMMAND,
                "灯光设备必须声明 lighting 分类及完整的受支持能力",
            )
        light = self._light(device_id, name, room_id, 60)
        light["_removable"] = True
        return light

    def execute(
        self,
        device: dict[str, Any],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
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

    def tick(self, device: dict[str, Any], context: DriverContext) -> bool:
        if not device["online"] or not device["automation"]["enabled"]:
            return False
        environment = context.find_first("environment", device["roomId"])
        if environment is None or not environment["online"]:
            return False
        now = time.time()
        override_until = device["automation"]["manualOverrideUntil"]
        if override_until is not None and now_ms() < override_until:
            return False
        if (
            environment["presence"]
            and environment["illuminanceLux"]
            < device["automation"]["illuminanceThresholdLux"]
        ):
            device["_noPresenceSince"] = None
            if not device["power"]:
                device["power"] = True
                device["brightness"] = max(1, device["lastNonZeroBrightness"])
                return True
            return False
        if not environment["presence"]:
            if device["_noPresenceSince"] is None:
                device["_noPresenceSince"] = now
            elif (
                device["power"]
                and now - device["_noPresenceSince"]
                >= device["automation"]["noPresenceDelaySeconds"]
            ):
                device["power"] = False
                return True
        return False


class EnvironmentDriver(DeviceDriver):
    device_type = "environment"
    tick_priority = 10
    registration_capabilities = {
        "reportTemperature",
        "reportHumidity",
        "reportIlluminance",
        "reportPresence",
    }

    def create_categories(self) -> list[dict[str, Any]]:
        return [
            {
                "id": "environment",
                "title": "环境",
                "icon": "≈",
                "homeOnly": False,
            }
        ]

    def create_devices(self) -> list[dict[str, Any]]:
        return [
            self._sensor("env-living-01", "客厅环境传感器", "living", 24.0, 55.0, 80.0),
            self._sensor("env-master-01", "主卧环境传感器", "masterBedroom", 23.4, 52.0, 130.0),
            self._sensor("env-bedroom-01", "次卧环境传感器", "bedroom", 24.2, 54.0, 95.0),
        ]

    def _sensor(
        self,
        device_id: str,
        name: str,
        room_id: str,
        temperature: float,
        humidity: float,
        illuminance: float,
    ) -> dict[str, Any]:
        environment = base_device(device_id, name, room_id, self.device_type)
        environment.update(
            {
                "_categoryId": "environment",
                "temperatureCelsius": temperature,
                "humidityPercent": humidity,
                "illuminanceLux": illuminance,
                "presence": True,
                "dataValid": True,
                "_manualInjectionUntil": 0.0,
            }
        )
        return environment

    def attest_registration(
        self,
        device_id: str,
        name: str,
        room_id: str,
        category_id: str,
        capabilities: list[str],
    ) -> dict[str, Any]:
        if (
            category_id != "environment"
            or set(capabilities) != self.registration_capabilities
        ):
            raise GatewayError(
                INVALID_COMMAND,
                "环境监测器必须声明 environment 分类及完整的受支持上报能力",
            )
        sensor = self._sensor(device_id, name, room_id, 24.0, 62.0, 95.0)
        sensor["presence"] = False
        sensor["_removable"] = True
        return sensor

    def tick(self, device: dict[str, Any], context: DriverContext) -> bool:
        now = time.time()
        changed = False
        if device["online"] and now >= device["_manualInjectionUntil"]:
            phase = now / 180
            target_temp = 24.0 + math.sin(phase) * 0.4
            target_humidity = 55.0 + math.sin(phase / 2) * 1.5
            air_conditioner = context.find_first("airConditioner", device["roomId"])
            if (
                air_conditioner is not None
                and air_conditioner["online"]
                and air_conditioner["power"]
            ):
                mode = air_conditioner["mode"]
                if mode in {"cool", "heat", "auto"}:
                    target_temp = float(air_conditioner["targetTemperatureCelsius"])
                if mode == "dry":
                    target_humidity = 50.0
            old_temp = device["temperatureCelsius"]
            old_humidity = device["humidityPercent"]
            device["temperatureCelsius"] = round(
                old_temp
                + (target_temp - old_temp) * 0.08
                + random.uniform(-0.02, 0.02),
                1,
            )
            device["humidityPercent"] = round(
                old_humidity
                + (target_humidity - old_humidity) * 0.06
                + random.uniform(-0.05, 0.05),
                1,
            )
            device["illuminanceLux"] = round(max(0.0, 120 + math.sin(now / 60) * 80), 1)
            changed = True

        if device["online"]:
            context.storage.record_environment(
                timestamp_ms=now_ms(),
                device_id=device["id"],
                temperature_celsius=device["temperatureCelsius"],
                humidity_percent=device["humidityPercent"],
                illuminance_lux=device["illuminanceLux"],
                presence=device["presence"],
            )

        data_valid = not (
            device["temperatureCelsius"] < -10
            or device["temperatureCelsius"] > 45
            or device["humidityPercent"] < 0
            or device["humidityPercent"] > 100
        )
        if data_valid != device["dataValid"]:
            device["dataValid"] = data_valid
            changed = True
        return changed


class AirConditionerDriver(DeviceDriver):
    device_type = "airConditioner"
    tick_priority = 20
    registration_capabilities = {
        "setPower",
        "setMode",
        "setTemperature",
        "setFanSpeed",
        "setDehumidify",
        "setBrand",
    }

    def create_devices(self) -> list[dict[str, Any]]:
        return [
            self._air_conditioner("ac-living-01", "客厅空调", "living", "haierSim", 24),
            self._air_conditioner(
                "ac-master-01", "主卧空调", "masterBedroom", "greeSim", 26
            ),
            self._air_conditioner("ac-bedroom-01", "次卧空调", "bedroom", "mideaSim", 25),
        ]

    def _air_conditioner(
        self,
        device_id: str,
        name: str,
        room_id: str,
        brand: str,
        temperature: int,
    ) -> dict[str, Any]:
        air_conditioner = base_device(device_id, name, room_id, self.device_type)
        air_conditioner.update(
            {
                "_categoryId": "environment",
                "brand": brand,
                "power": False,
                "mode": "auto",
                "targetTemperatureCelsius": temperature,
                "fanSpeed": "auto",
                "running": False,
                "lastAdapterFrame": "",
            }
        )
        return air_conditioner

    def attest_registration(
        self,
        device_id: str,
        name: str,
        room_id: str,
        category_id: str,
        capabilities: list[str],
    ) -> dict[str, Any]:
        if (
            category_id != "environment"
            or set(capabilities) != self.registration_capabilities
        ):
            raise GatewayError(
                INVALID_COMMAND,
                "空调必须声明 environment 分类及完整的受支持控制能力",
            )
        air_conditioner = self._air_conditioner(
            device_id, name, room_id, "generic", 24
        )
        air_conditioner["_removable"] = True
        return air_conditioner

    def execute(
        self,
        device: dict[str, Any],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
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
            command = NormalizedAcCommand(action=action, temperature=temperature)
            device["targetTemperatureCelsius"] = temperature
        elif action == "setFanSpeed":
            fan_speed = payload.get("fanSpeed")
            if not isinstance(fan_speed, str):
                raise GatewayError(INVALID_COMMAND, "空调风速参数无效")
            command = NormalizedAcCommand(action=action, fan_speed=fan_speed)
            device["fanSpeed"] = fan_speed
        elif action == "setDehumidify":
            enabled = payload.get("enabled")
            if not isinstance(enabled, bool):
                raise GatewayError(INVALID_COMMAND, "Invalid dehumidify switch")
            device["mode"] = "dry"
            device["power"] = enabled
            device["running"] = enabled
            command = NormalizedAcCommand(action="setMode", mode="dry")
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


class BathHeaterDriver(DeviceDriver):
    """A bathroom heater that belongs to the environment category."""

    device_type = "bathHeater"
    tick_priority = 25

    def create_devices(self) -> list[dict[str, Any]]:
        bath_heater = base_device(
            "bath-heater-bathroom-01", "浴室智能浴霸", "bathroom", self.device_type
        )
        bath_heater.update(
            {
                "_categoryId": "environment",
                "state": {"power": False, "mode": "warm"},
                "controls": [
                    {
                        "id": "power",
                        "kind": "toggle",
                        "label": "开关",
                        "action": "setPower",
                        "stateKey": "power",
                        "payloadKey": "power",
                        "primary": True,
                    },
                    {
                        "id": "mode",
                        "kind": "enum",
                        "label": "工作模式",
                        "action": "setMode",
                        "stateKey": "mode",
                        "payloadKey": "mode",
                        "options": [
                            {"value": "warm", "label": "暖风"},
                            {"value": "ventilate", "label": "换气"},
                            {"value": "dry", "label": "干燥"},
                        ],
                    },
                ],
            }
        )
        return [bath_heater]

    def execute(
        self,
        device: dict[str, Any],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
    ) -> None:
        state = device["state"]
        if action == "setPower":
            power = payload.get("power")
            if not isinstance(power, bool):
                raise GatewayError(INVALID_COMMAND, "浴霸开关参数无效")
            state["power"] = power
            return
        if action == "setMode":
            mode = payload.get("mode")
            if not isinstance(mode, str) or mode not in {"warm", "ventilate", "dry"}:
                raise GatewayError(INVALID_COMMAND, "浴霸工作模式无效")
            state["mode"] = mode
            return
        raise GatewayError(INVALID_COMMAND, "浴霸动作不受支持")


class HumidifierDriver(DeviceDriver):
    """A living-room humidifier in the environment category."""

    device_type = "humidifier"
    tick_priority = 24
    registration_capabilities = {"setPower", "setTargetHumidity"}

    def create_devices(self) -> list[dict[str, Any]]:
        return [self._humidifier("humidifier-living-01", "客厅加湿器", "living")]

    def _humidifier(
        self, device_id: str, name: str, room_id: str
    ) -> dict[str, Any]:
        humidifier = base_device(device_id, name, room_id, self.device_type)
        humidifier.update(
            {
                "_categoryId": "environment",
                "state": {"power": False, "targetHumidityPercent": 55},
                "controls": [
                    {
                        "id": "power",
                        "kind": "toggle",
                        "label": "开关",
                        "action": "setPower",
                        "stateKey": "power",
                        "payloadKey": "power",
                        "primary": True,
                    },
                    {
                        "id": "targetHumidity",
                        "kind": "slider",
                        "label": "目标湿度",
                        "action": "setTargetHumidity",
                        "stateKey": "targetHumidityPercent",
                        "payloadKey": "targetHumidityPercent",
                        "minimum": 35,
                        "maximum": 75,
                        "step": 1,
                        "unit": "%",
                    },
                ],
            }
        )
        return humidifier

    def attest_registration(
        self,
        device_id: str,
        name: str,
        room_id: str,
        category_id: str,
        capabilities: list[str],
    ) -> dict[str, Any]:
        if (
            category_id != "environment"
            or set(capabilities) != self.registration_capabilities
        ):
            raise GatewayError(
                INVALID_COMMAND,
                "加湿器必须声明 environment 分类及完整的受支持控制能力",
            )
        humidifier = self._humidifier(device_id, name, room_id)
        humidifier["_removable"] = True
        return humidifier

    def execute(
        self,
        device: dict[str, Any],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
    ) -> None:
        state = device["state"]
        if action == "setPower":
            power = payload.get("power")
            if not isinstance(power, bool):
                raise GatewayError(INVALID_COMMAND, "加湿器开关参数无效")
            state["power"] = power
            return
        if action == "setTargetHumidity":
            target = payload.get("targetHumidityPercent")
            if (
                isinstance(target, bool)
                or not isinstance(target, (int, float))
                or target < 35
                or target > 75
            ):
                raise GatewayError(INVALID_COMMAND, "目标湿度必须在35到75之间")
            state["targetHumidityPercent"] = int(round(target))
            return
        raise GatewayError(INVALID_COMMAND, "加湿器动作不受支持")


class DoorLockDriver(DeviceDriver):
    device_type = "doorLock"
    tick_priority = 40
    requires_category = False

    def create_devices(self) -> list[dict[str, Any]]:
        door = base_device("door-entry-01", "入户门锁", "entry", self.device_type)
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
        return [door]

    def execute(
        self,
        device: dict[str, Any],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
    ) -> None:
        if device["jammed"] and action in {"lock", "unlock"}:
            context.record_alert(
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

    def tick(self, device: dict[str, Any], context: DriverContext) -> bool:
        auto_lock_at = device["autoLockAt"]
        if (
            device["online"]
            and not device["locked"]
            and device["autoLockEnabled"]
            and auto_lock_at is not None
            and now_ms() >= auto_lock_at
        ):
            device["locked"] = True
            device["autoLockAt"] = None
            context.storage.record_audit(
                timestamp_ms=now_ms(),
                client_id="gateway-rule",
                device_id=device["id"],
                action="autoLock",
                result="success",
                error_code=None,
                message_id="auto-lock",
            )
            return True
        return False


class CurtainDriver(DeviceDriver):
    device_type = "curtain"
    tick_priority = 50

    def create_categories(self) -> list[dict[str, Any]]:
        return [
            {
                "id": "curtains",
                "title": "窗帘",
                "icon": "curtain",
                "homeOnly": False,
            }
        ]

    def create_devices(self) -> list[dict[str, Any]]:
        return [
            self._curtain("curtain-living-01", "客厅智能窗帘", "living"),
            self._curtain("curtain-master-01", "主卧智能窗帘", "masterBedroom"),
            self._curtain("curtain-bedroom-01", "次卧智能窗帘", "bedroom"),
        ]

    def _curtain(
        self, device_id: str, name: str, room_id: str
    ) -> dict[str, Any]:
        curtain = base_device(device_id, name, room_id, self.device_type)
        curtain.update(
            {
                "_categoryId": "curtains",
                "state": {
                    "positionPercent": 0,
                    "targetPositionPercent": 0,
                    "movement": "stopped",
                },
                "controls": [
                    {
                        "id": "position",
                        "kind": "slider",
                        "label": "开合度",
                        "action": "setPosition",
                        "stateKey": "positionPercent",
                        "payloadKey": "positionPercent",
                        "minimum": 0,
                        "maximum": 100,
                        "step": 1,
                        "unit": "%",
                        "primary": True,
                        "requiresConfirmation": False,
                    },
                    {
                        "id": "open",
                        "kind": "button",
                        "label": "打开",
                        "action": "open",
                    },
                    {
                        "id": "stop",
                        "kind": "button",
                        "label": "暂停",
                        "action": "stop",
                    },
                    {
                        "id": "close",
                        "kind": "button",
                        "label": "关闭",
                        "action": "close",
                    },
                ],
            }
        )
        return curtain

    def execute(
        self,
        device: dict[str, Any],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
    ) -> None:
        state = device["state"]
        current = int(state["positionPercent"])
        if action == "open":
            target = 100
        elif action == "close":
            target = 0
        elif action == "stop":
            target = current
        elif action == "setPosition":
            target_value = payload.get("positionPercent")
            if (
                isinstance(target_value, bool)
                or not isinstance(target_value, int)
                or target_value < 0
                or target_value > 100
            ):
                raise GatewayError(INVALID_COMMAND, "窗帘开合度必须为0到100的整数")
            target = target_value
        else:
            raise GatewayError(INVALID_COMMAND, "窗帘动作不受支持")
        state["targetPositionPercent"] = target
        if target > current:
            state["movement"] = "opening"
        elif target < current:
            state["movement"] = "closing"
        else:
            state["movement"] = "stopped"

    def tick(self, device: dict[str, Any], context: DriverContext) -> bool:
        if not device["online"]:
            return False
        state = device["state"]
        current = int(state["positionPercent"])
        target = int(state["targetPositionPercent"])
        if current == target:
            if state["movement"] != "stopped":
                state["movement"] = "stopped"
                return True
            return False
        step = min(10, abs(target - current))
        if target > current:
            current += step
            state["movement"] = "opening"
        else:
            current -= step
            state["movement"] = "closing"
        state["positionPercent"] = current
        if current == target:
            state["movement"] = "stopped"
        return True
