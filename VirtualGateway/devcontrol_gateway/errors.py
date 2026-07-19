from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class GatewayError(Exception):
    code: str
    message: str
    status_code: int = 400
    retry_after_seconds: int | None = None

    def to_dict(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "error": {
                "code": self.code,
                "message": self.message,
            }
        }
        if self.retry_after_seconds is not None:
            payload["error"]["retryAfterSeconds"] = self.retry_after_seconds
        return payload


AUTH_FAILED = "AUTH_FAILED"
DEVICE_PROOF_INVALID = "DEVICE_PROOF_INVALID"
DEVICE_OFFLINE = "DEVICE_OFFLINE"
INVALID_COMMAND = "INVALID_COMMAND"
COMMAND_TIMEOUT = "COMMAND_TIMEOUT"
STATE_CONFLICT = "STATE_CONFLICT"
REPLAY_DETECTED = "REPLAY_DETECTED"
RATE_LIMITED = "RATE_LIMITED"
INTERNAL_ERROR = "INTERNAL_ERROR"

