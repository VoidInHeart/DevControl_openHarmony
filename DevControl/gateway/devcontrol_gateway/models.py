from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal


GatewayErrorCode = Literal[
    "AUTH_FAILED",
    "DEVICE_OFFLINE",
    "INVALID_COMMAND",
    "COMMAND_TIMEOUT",
    "STATE_CONFLICT",
    "REPLAY_DETECTED",
    "RATE_LIMITED",
    "INTERNAL_ERROR",
]


@dataclass(slots=True)
class Device:
    id: str
    name: str
    room_id: str
    type: Literal["light", "environment", "airConditioner", "doorLock"]
    state: dict[str, Any]
    brand: str = "generic"
    online: bool = True
    state_version: int = 1
    updated_at: int = 0

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "roomId": self.room_id,
            "type": self.type,
            "brand": self.brand,
            "online": self.online,
            "stateVersion": self.state_version,
            "updatedAt": self.updated_at,
            "state": dict(self.state),
        }


@dataclass(frozen=True, slots=True)
class ClientSession:
    client_id: str
    credential_digest: str
    data_key: bytes
    expires_at: int


@dataclass(slots=True)
class CommandOutcome:
    result: dict[str, Any]
    changed_devices: list[Device] = field(default_factory=list)
    alerts: list[dict[str, Any]] = field(default_factory=list)
