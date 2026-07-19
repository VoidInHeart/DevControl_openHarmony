from __future__ import annotations

from .drivers import (
    AirConditionerDriver,
    BathHeaterDriver,
    CurtainDriver,
    DeviceDriver,
    DoorLockDriver,
    EnvironmentDriver,
    HumidifierDriver,
    LightDriver,
)


def default_drivers() -> list[DeviceDriver]:
    """Register the project's built-in device families."""

    return [
        LightDriver(),
        EnvironmentDriver(),
        HumidifierDriver(),
        BathHeaterDriver(),
        AirConditionerDriver(),
        DoorLockDriver(),
        CurtainDriver(),
    ]
