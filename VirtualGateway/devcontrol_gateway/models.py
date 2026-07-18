from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


PROTOCOL_VERSION = "1.0"


class PairRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocolVersion: Literal["1.0"] = PROTOCOL_VERSION
    pairingCode: str = Field(pattern=r"^\d{6}$")
    clientId: str = Field(min_length=8, max_length=128)


class PairResponse(BaseModel):
    protocolVersion: Literal["1.0"] = PROTOCOL_VERSION
    clientId: str
    credential: str
    dataKey: str
    issuedAt: int
    expiresAt: int


class SecureCommandEnvelope(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocolVersion: Literal["1.0"] = PROTOCOL_VERSION
    messageId: str = Field(min_length=16, max_length=128)
    deviceId: str = Field(min_length=3, max_length=128)
    timestamp: int
    type: Literal["command.request"] = "command.request"
    action: str = Field(min_length=1, max_length=64)
    expectedStateVersion: int | None = Field(default=None, ge=0)
    nonce: str = Field(min_length=16, max_length=32)
    ciphertext: str = Field(min_length=1, max_length=32_768)
    authTag: str = Field(min_length=16, max_length=32)

    @field_validator("messageId", "nonce", "ciphertext", "authTag")
    @classmethod
    def base64url_only(cls, value: str) -> str:
        allowed = set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        if any(character not in allowed for character in value):
            raise ValueError("must use unpadded base64url")
        return value


class FaultRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    online: bool | None = None
    jammed: bool | None = None
    batteryPercent: int | None = Field(default=None, ge=0, le=100)
    commandDelayMs: int | None = Field(default=None, ge=0, le=30_000)
    failNextCommand: bool | None = None


class EnvironmentInjection(BaseModel):
    model_config = ConfigDict(extra="forbid")

    temperatureCelsius: float | None = Field(default=None, ge=-50, le=80)
    humidityPercent: float | None = Field(default=None, ge=0, le=100)
    illuminanceLux: float | None = Field(default=None, ge=0, le=100_000)
    presence: bool | None = None


JsonObject = dict[str, Any]

