from __future__ import annotations

from pathlib import Path

import pytest

from devcontrol_gateway.drivers import DeviceDriver, DriverContext, base_device
from devcontrol_gateway.errors import DEVICE_OFFLINE, INVALID_COMMAND, GatewayError
from devcontrol_gateway.registry import DeviceRegistry
from devcontrol_gateway.storage import GatewayStorage


class FakeSwitchDriver(DeviceDriver):
    device_type = "fakeSwitch"

    def create_categories(self) -> list[dict[str, object]]:
        return [
            {
                "id": "test-switches",
                "title": "测试开关",
                "icon": "○",
                "homeOnly": False,
            }
        ]

    def create_devices(self) -> list[dict[str, object]]:
        device = base_device(
            "fake-switch-01", "测试开关", "test-room", self.device_type
        )
        device["_categoryId"] = "test-switches"
        device["power"] = False
        return [device]

    def execute(
        self,
        device: dict[str, object],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
    ) -> None:
        if action != "setPower" or not isinstance(payload.get("power"), bool):
            raise GatewayError(INVALID_COMMAND, "命令参数无效")
        device["power"] = payload["power"]


class DuplicateTypeDriver(FakeSwitchDriver):
    def create_devices(self) -> list[dict[str, object]]:
        return [
            base_device("another-fake-01", "重复类型", "test-room", self.device_type)
        ]


class DuplicateIdDriver(FakeSwitchDriver):
    device_type = "otherSwitch"

    def create_categories(self) -> list[dict[str, object]]:
        return [
            {
                "id": "other-switches",
                "title": "其他开关",
                "icon": "○",
                "homeOnly": False,
            }
        ]

    def create_devices(self) -> list[dict[str, object]]:
        device = base_device("fake-switch-01", "重复设备", "test-room", self.device_type)
        device["_categoryId"] = "other-switches"
        return [device]


class MissingCategoryDriver(DeviceDriver):
    device_type = "missingCategory"

    def create_devices(self) -> list[dict[str, object]]:
        device = base_device(
            "missing-category-01", "缺少分类", "test-room", self.device_type
        )
        device["power"] = False
        return [device]


@pytest.fixture
def storage(tmp_path: Path):
    value = GatewayStorage(tmp_path / "drivers.db")
    yield value
    value.close()


def test_new_driver_registers_and_dispatches_without_registry_changes(
    storage: GatewayStorage,
) -> None:
    registry = DeviceRegistry(storage, drivers=[])
    registry.register_driver(FakeSwitchDriver())
    device = registry.get("fake-switch-01")

    result, details = registry.execute(
        device["id"],
        "setPower",
        {"power": True},
        device["stateVersion"],
    )

    assert details is None
    assert result is not None
    assert result["power"] is True
    assert result["stateVersion"] == 2


def test_duplicate_driver_type_and_device_id_fail_fast(
    storage: GatewayStorage,
) -> None:
    registry = DeviceRegistry(storage, drivers=[FakeSwitchDriver()])
    with pytest.raises(ValueError, match="driver type"):
        registry.register_driver(DuplicateTypeDriver())
    with pytest.raises(ValueError, match="device id"):
        registry.register_driver(DuplicateIdDriver())


def test_common_offline_check_applies_to_registered_drivers(
    storage: GatewayStorage,
) -> None:
    registry = DeviceRegistry(storage, drivers=[FakeSwitchDriver()])
    registry.inject_fault("fake-switch-01", {"online": False})
    device = registry.get("fake-switch-01")

    with pytest.raises(GatewayError) as failure:
        registry.execute(
            device["id"],
            "setPower",
            {"power": True},
            device["stateVersion"],
        )

    assert failure.value.code == DEVICE_OFFLINE


def test_devices_must_reference_a_registered_category(
    storage: GatewayStorage,
) -> None:
    registry = DeviceRegistry(storage, drivers=[])

    with pytest.raises(ValueError, match="registered category"):
        registry.register_driver(MissingCategoryDriver())


def test_default_registry_restores_bedroom_devices_and_bath_heater(
    storage: GatewayStorage,
) -> None:
    registry = DeviceRegistry(storage)
    expected_ids = {
        "light-master-01",
        "light-bedroom-01",
        "env-master-01",
        "env-bedroom-01",
        "ac-master-01",
        "ac-bedroom-01",
        "curtain-master-01",
        "curtain-bedroom-01",
        "bath-heater-bathroom-01",
        "humidifier-living-01",
    }

    assert expected_ids.issubset(registry.devices)
    assert registry.categories["environment"]["title"] == "环境"
    snapshot = {item["id"]: item for item in registry.snapshot()}
    assert snapshot["light-living-01"]["category"]["id"] == "lighting"
    assert snapshot["env-living-01"]["category"]["id"] == "environment"
    assert snapshot["ac-living-01"]["category"]["id"] == "environment"
    assert snapshot["curtain-living-01"]["category"]["id"] == "curtains"
    assert snapshot["humidifier-living-01"]["category"]["id"] == "environment"
    assert "category" not in snapshot["door-entry-01"]
    bath_heater = registry.get("bath-heater-bathroom-01")
    assert bath_heater["_categoryId"] == "environment"
    public_bath_heater = snapshot[bath_heater["id"]]
    assert public_bath_heater["category"]["id"] == "environment"

    result, _ = registry.execute(
        bath_heater["id"], "setPower", {"power": True}, bath_heater["stateVersion"]
    )
    assert result is not None
    assert result["state"]["power"] is True

    humidifier = registry.get("humidifier-living-01")
    result, _ = registry.execute(
        humidifier["id"],
        "setTargetHumidity",
        {"targetHumidityPercent": 60},
        humidifier["stateVersion"],
    )
    assert result is not None
    assert result["state"]["targetHumidityPercent"] == 60


def test_curtain_commands_and_ticks_progress_authoritative_state(
    storage: GatewayStorage,
) -> None:
    registry = DeviceRegistry(storage)
    curtain = registry.get("curtain-living-01")
    assert curtain["_categoryId"] == "curtains"
    snapshot = registry.snapshot()
    public_curtain = next(item for item in snapshot if item["id"] == curtain["id"])
    assert public_curtain["category"]["id"] == "curtains"
    assert curtain["controls"][0]["kind"] == "slider"

    result, _ = registry.execute(
        curtain["id"],
        "setPosition",
        {"positionPercent": 35},
        curtain["stateVersion"],
    )
    assert result is not None
    assert result["state"]["targetPositionPercent"] == 35
    assert result["state"]["movement"] == "opening"

    changed = registry.tick()
    curtain_events = [item for item in changed if item["id"] == "curtain-living-01"]
    assert curtain_events[0]["state"]["positionPercent"] == 10

    curtain = registry.get("curtain-living-01")
    registry.execute(curtain["id"], "stop", {}, curtain["stateVersion"])
    assert curtain["state"]["targetPositionPercent"] == 10
    assert curtain["state"]["movement"] == "stopped"

    with pytest.raises(GatewayError) as invalid:
        registry.execute(
            curtain["id"],
            "setPosition",
            {"positionPercent": 101},
            curtain["stateVersion"],
        )
    assert invalid.value.code == INVALID_COMMAND

    curtain = registry.get("curtain-living-01")
    registry.execute(curtain["id"], "open", {}, curtain["stateVersion"])
    for _ in range(9):
        registry.tick()
    assert curtain["state"]["positionPercent"] == 100
    assert curtain["state"]["movement"] == "stopped"

    registry.execute(curtain["id"], "close", {}, curtain["stateVersion"])
    registry.tick()
    assert curtain["state"]["positionPercent"] == 90
    assert curtain["state"]["movement"] == "closing"
