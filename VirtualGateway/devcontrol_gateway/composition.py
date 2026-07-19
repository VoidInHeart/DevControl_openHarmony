from __future__ import annotations

from .drivers import (
    AirConditionerDriver,
    CurtainDriver,
    DeviceDriver,
    DoorLockDriver,
    EnvironmentDriver,
    LightDriver,
)


def default_drivers() -> list[DeviceDriver]:
    """Register device families; each driver registers its categories first."""
    return [
        LightDriver(),
        EnvironmentDriver(),
        AirConditionerDriver(),
        DoorLockDriver(),
        CurtainDriver(),
    ]
