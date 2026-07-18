from __future__ import annotations

from .drivers import (
    AirConditionerDriver,
    CurtainDriver,
    DeviceDriver,
    DoorLockDriver,
    EnvironmentDriver,
    LightDriver,
)
from .extensions.virtual_fan import VirtualFanDriver


def default_drivers(include_demo_extensions: bool = True) -> list[DeviceDriver]:
    """The only composition root for project-owned device drivers."""

    drivers: list[DeviceDriver] = [
        LightDriver(),
        EnvironmentDriver(),
        AirConditionerDriver(),
        DoorLockDriver(),
        CurtainDriver(),
    ]
    if include_demo_extensions:
        drivers.append(VirtualFanDriver())
    return drivers
