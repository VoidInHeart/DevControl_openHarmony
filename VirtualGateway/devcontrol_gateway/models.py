from __future__ import annotations

import re
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


PROTOCOL_VERSION = "1.0"
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9._-]{0,63}$")
DEVICE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{2,63}$")
DEVICE_NAME_PATTERN = re.compile(r"^[^\x00-\x1F\x7F]{1,64}$")
COMPACT_JWS_PATTERN = re.compile(
    r"^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$"
)


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


class DeviceProvisionRequest(BaseModel):
    """A declaration that may be signed only by the local provisioning API."""

    model_config = ConfigDict(extra="forbid")
    protocolVersion: Literal["1.0"] = PROTOCOL_VERSION
    deviceId: str = Field(min_length=3, max_length=64)
    deviceName: str = Field(min_length=1, max_length=64)
    deviceType: str = Field(min_length=1, max_length=64)
    categoryId: str = Field(min_length=1, max_length=64)
    roomId: str = Field(min_length=1, max_length=64)
    capabilities: list[str] = Field(min_length=1, max_length=32)

    @field_validator("deviceId")
    @classmethod
    def valid_device_id(cls, value: str) -> str:
        if not DEVICE_ID_PATTERN.fullmatch(value):
            raise ValueError("deviceId has an invalid format")
        return value

    @field_validator("deviceName")
    @classmethod
    def valid_device_name(cls, value: str) -> str:
        if not DEVICE_NAME_PATTERN.fullmatch(value) or not value.strip():
            raise ValueError("deviceName must be visible text and cannot be blank")
        return value

    @field_validator("deviceType", "categoryId", "roomId")
    @classmethod
    def valid_identifier(cls, value: str) -> str:
        if not IDENTIFIER_PATTERN.fullmatch(value):
            raise ValueError("identifier has an invalid format")
        return value

    @field_validator("capabilities")
    @classmethod
    def valid_capabilities(cls, value: list[str]) -> list[str]:
        if len(value) != len(set(value)) or any(
            not IDENTIFIER_PATTERN.fullmatch(item) for item in value
        ):
            raise ValueError("capabilities must be unique identifiers")
        return value


class DeviceRegistrationRequest(DeviceProvisionRequest):
    gatewayProofFormat: Literal["jws"] = "jws"
    gatewayProof: str = Field(min_length=25, max_length=4096)

    @model_validator(mode="before")
    @classmethod
    def require_and_strip_schema(cls, value: object) -> object:
        if not isinstance(value, dict):
            raise ValueError("device registration request must be an object")
        if value.get("schema") != "devcontrol.device-registration":
            raise ValueError("unsupported device registration schema")
        sanitized = dict(value)
        del sanitized["schema"]
        return sanitized

    @field_validator("gatewayProof")
    @classmethod
    def valid_gateway_proof(cls, value: str) -> str:
        if not COMPACT_JWS_PATTERN.fullmatch(value):
            raise ValueError("gatewayProof must be a compact JWS")
        return value


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

