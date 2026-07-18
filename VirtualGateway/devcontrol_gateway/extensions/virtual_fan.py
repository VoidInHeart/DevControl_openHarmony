from __future__ import annotations

from typing import Any

from ..drivers import DeviceDriver, DriverContext, base_device
from ..errors import INVALID_COMMAND, GatewayError


class VirtualFanDriver(DeviceDriver):
    """A proof device added without changing registry or APP domain branches."""

    device_type = "fan"

    def create_devices(self) -> list[dict[str, Any]]:
        fan = base_device(
            "fan-bedroom-01",
            "卧室循环风扇",
            "bedroom",
            self.device_type,
        )
        fan.update(
            {
                "category": {
                    "id": "fans",
                    "title": "风扇",
                    "icon": "🌀",
                    "homeOnly": False,
                },
                "state": {
                    "power": False,
                    "speed": "medium",
                    "oscillating": False,
                },
                "controls": [
                    {
                        "id": "power",
                        "kind": "toggle",
                        "label": "电源",
                        "action": "setPower",
                        "stateKey": "power",
                        "payloadKey": "power",
                        "primary": True,
                    },
                    {
                        "id": "speed",
                        "kind": "enum",
                        "label": "风速",
                        "action": "setSpeed",
                        "stateKey": "speed",
                        "payloadKey": "speed",
                        "options": [
                            {"value": "low", "label": "低速"},
                            {"value": "medium", "label": "中速"},
                            {"value": "high", "label": "高速"},
                        ],
                    },
                    {
                        "id": "oscillation",
                        "kind": "toggle",
                        "label": "摇头",
                        "action": "setOscillating",
                        "stateKey": "oscillating",
                        "payloadKey": "oscillating",
                    },
                ],
            }
        )
        return [fan]

    def execute(
        self,
        device: dict[str, Any],
        action: str,
        payload: dict[str, object],
        context: DriverContext,
    ) -> None:
        del context
        state = device["state"]
        if action == "setPower":
            power = payload.get("power")
            if not isinstance(power, bool):
                raise GatewayError(INVALID_COMMAND, "风扇电源参数必须为布尔值")
            state["power"] = power
            return
        if action == "setSpeed":
            speed = payload.get("speed")
            if not isinstance(speed, str) or speed not in {"low", "medium", "high"}:
                raise GatewayError(INVALID_COMMAND, "风速必须为 low、medium 或 high")
            state["speed"] = speed
            return
        if action == "setOscillating":
            oscillating = payload.get("oscillating")
            if not isinstance(oscillating, bool):
                raise GatewayError(INVALID_COMMAND, "摇头参数必须为布尔值")
            state["oscillating"] = oscillating
            return
        raise GatewayError(INVALID_COMMAND, "风扇动作不受支持")
