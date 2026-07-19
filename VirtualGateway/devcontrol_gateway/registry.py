from __future__ import annotations

import copy
import time
from collections.abc import Iterable
from typing import Any

from .composition import default_drivers
from .drivers import DeviceDriver, iso_now
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


class DeviceRegistry:
    """Routes devices to explicitly registered family drivers."""

    def __init__(
        self,
        storage: GatewayStorage,
        drivers: Iterable[DeviceDriver] | None = None,
    ) -> None:
        self.storage = storage
        self._pending_alerts: list[dict[str, Any]] = []
        self.categories: dict[str, dict[str, Any]] = {}
        self.drivers: dict[str, DeviceDriver] = {}
        self.devices: dict[str, dict[str, Any]] = {}
        for driver in drivers if drivers is not None else default_drivers():
            self.register_driver(driver)

    def register_driver(self, driver: DeviceDriver) -> None:
        device_type = driver.device_type
        if not device_type or device_type in self.drivers:
            raise ValueError(f"duplicate or empty device driver type: {device_type}")
        new_categories = self._validate_categories(driver)
        created = driver.create_devices()
        registered_category_ids = set(self.categories) | set(new_categories)
        new_ids: set[str] = set()
        for device in created:
            device_id = device.get("id")
            if not isinstance(device_id, str) or not device_id:
                raise ValueError(f"driver {device_type} created a device without an id")
            if device.get("type") != device_type:
                raise ValueError(
                    f"driver {device_type} created mismatched type {device.get('type')}"
                )
            if device_id in self.devices or device_id in new_ids:
                raise ValueError(f"duplicate device id: {device_id}")
            if "category" in device:
                raise ValueError(
                    f"driver {device_type} must register categories separately"
                )
            if driver.requires_category:
                category_id = device.get("_categoryId")
                if (
                    not isinstance(category_id, str)
                    or category_id not in registered_category_ids
                ):
                    raise ValueError(
                        f"driver {device_type} created a device without a registered category"
                    )
            new_ids.add(device_id)
        self.categories.update(new_categories)
        self.drivers[device_type] = driver
        for device in created:
            self.devices[device["id"]] = device

    def _validate_categories(self, driver: DeviceDriver) -> dict[str, dict[str, Any]]:
        categories: dict[str, dict[str, Any]] = {}
        for category in driver.create_categories():
            category_id = category.get("id")
            title = category.get("title")
            icon = category.get("icon")
            home_only = category.get("homeOnly")
            if (
                not isinstance(category_id, str)
                or not category_id
                or not isinstance(title, str)
                or not title
                or not isinstance(icon, str)
                or not icon
                or not isinstance(home_only, bool)
            ):
                raise ValueError(
                    f"driver {driver.device_type} created an invalid category"
                )
            if category_id in self.categories or category_id in categories:
                raise ValueError(f"duplicate category id: {category_id}")
            categories[category_id] = copy.deepcopy(category)
        return categories

    def snapshot(self) -> list[dict[str, Any]]:
        return [self.public_device(device) for device in self.devices.values()]

    def public_device(self, device: dict[str, Any]) -> dict[str, Any]:
        public = copy.deepcopy(
            {key: value for key, value in device.items() if not key.startswith("_")}
        )
        category_id = device.get("_categoryId")
        if isinstance(category_id, str):
            public["category"] = copy.deepcopy(self.categories[category_id])
        public["removable"] = device.get("_removable") is True
        return public

    def get(self, device_id: str) -> dict[str, Any]:
        device = self.devices.get(device_id)
        if device is None:
            raise GatewayError(INVALID_COMMAND, "目标设备不存在")
        return device

    def register_provisioned(
        self,
        *,
        device_id: str,
        name: str,
        room_id: str,
        device_type: str,
        category_id: str,
        capabilities: list[str],
    ) -> dict[str, Any]:
        driver = self.drivers.get(device_type)
        if driver is None:
            raise GatewayError(INVALID_COMMAND, "设备类型未注册")
        # The driver is the device-facing boundary: it verifies that this
        # declared type/category/capability set is actually accepted and can
        # currently come online before the gateway records the registration.
        device = driver.attest_registration(
            device_id,
            name,
            room_id,
            category_id,
            capabilities,
        )
        if (
            device.get("id") != device_id
            or device.get("type") != device_type
            or device.get("_categoryId") != category_id
            or not device.get("online", False)
        ):
            raise GatewayError(INTERNAL_ERROR, "设备驱动未返回可在线注册的设备")
        device["_registrationCapabilities"] = sorted(capabilities)

        existing = self.devices.get(device_id)
        if existing is not None:
            same_registration = (
                existing.get("_removable") is True
                and existing.get("name") == name
                and existing.get("roomId") == room_id
                and existing.get("type") == device_type
                and existing.get("_categoryId") == category_id
                and existing.get("_registrationCapabilities") == sorted(capabilities)
            )
            if same_registration:
                return self.public_device(existing)
            raise GatewayError(INVALID_COMMAND, "设备序列号已被另一份设备声明占用")
        self.devices[device_id] = device
        return self.public_device(device)

    def remove_provisioned(self, device_id: str) -> dict[str, Any]:
        device = self.get(device_id)
        if device.get("_removable") is not True:
            raise GatewayError(INVALID_COMMAND, "该内置设备不支持移除")
        public = self.public_device(device)
        del self.devices[device_id]
        return public

    def find_first(
        self, device_type: str, room_id: str | None = None
    ) -> dict[str, Any] | None:
        for device in self.devices.values():
            if device["type"] != device_type:
                continue
            if room_id is None or device["roomId"] == room_id:
                return device
        return None

    def _driver_for(self, device: dict[str, Any]) -> DeviceDriver:
        driver = self.drivers.get(str(device["type"]))
        if driver is None:
            raise GatewayError(INVALID_COMMAND, "设备类型未注册")
        return driver

    def _ensure_commandable(
        self, device: dict[str, Any], expected_version: int | None
    ) -> None:
        if not device["online"]:
            raise GatewayError(DEVICE_OFFLINE, "目标设备当前离线")
        if expected_version is not None and expected_version != device["stateVersion"]:
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
        if device_id == "scene-home":
            if action != "executeHome":
                raise GatewayError(INVALID_COMMAND, "场景动作不受支持")
            return None, self._execute_home()
        return self._execute_device(device_id, action, payload, expected_version), None

    def _execute_device(
        self,
        device_id: str,
        action: str,
        payload: dict[str, object],
        expected_version: int | None,
    ) -> dict[str, Any]:
        device = self.get(device_id)
        self._ensure_commandable(device, expected_version)
        self._driver_for(device).execute(device, action, payload, self)
        self._touch(device)
        return self.public_device(device)

    def _execute_away(self) -> list[dict[str, object]]:
        actions = (
            ("light-living-01", (("setPower", {"power": False}),)),
            ("ac-living-01", (("setPower", {"power": False}),)),
            ("door-entry-01", (("lock", {}),)),
        )
        return self._execute_scene_actions(actions)

    def _execute_home(self) -> list[dict[str, object]]:
        actions = (
            ("light-living-01", (("setBrightness", {"brightness": 70}),)),
            (
                "ac-living-01",
                (
                    ("setMode", {"mode": "auto"}),
                    ("setTemperature", {"temperatureCelsius": 24}),
                    ("setPower", {"power": True}),
                ),
            ),
            ("door-entry-01", (("lock", {}),)),
        )
        return self._execute_scene_actions(actions)

    def _execute_scene_actions(
        self,
        actions: tuple[tuple[str, tuple[tuple[str, dict[str, object]], ...]], ...],
    ) -> list[dict[str, object]]:
        results: list[dict[str, object]] = []
        for device_id, device_actions in actions:
            try:
                for action, payload in device_actions:
                    device = self.get(device_id)
                    self._execute_device(
                        device_id, action, payload, device["stateVersion"]
                    )
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
        ordered = sorted(
            self.devices.values(),
            key=lambda device: self._driver_for(device).tick_priority,
        )
        for device in ordered:
            driver = self._driver_for(device)
            if driver.tick(device, self):
                self._touch(device)
                changed.append(self.public_device(device))
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
                self.record_alert(
                    device_id,
                    "warning",
                    "LOW_BATTERY",
                    "门锁电量低于20%",
                )
        return self.public_device(device)

    def record_alert(
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

    def inject_environment(self, values: dict[str, object | None]) -> dict[str, Any]:
        environment = self.find_first("environment")
        if environment is None:
            raise GatewayError(INVALID_COMMAND, "环境传感器不存在")
        for key in (
            "temperatureCelsius",
            "humidityPercent",
            "illuminanceLux",
            "presence",
        ):
            value = values.get(key)
            if value is not None:
                environment[key] = value
        environment["_manualInjectionUntil"] = time.time() + 30
        self._touch(environment)
        return self.public_device(environment)
