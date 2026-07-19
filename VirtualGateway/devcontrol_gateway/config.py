from __future__ import annotations

import os
import re
import secrets
from dataclasses import dataclass
from pathlib import Path


def _optional_path(value: str | None) -> Path | None:
    return Path(value) if value else None


@dataclass(slots=True)
class GatewayConfig:
    host: str = "0.0.0.0"
    port: int = 8443
    admin_host: str = "127.0.0.1"
    admin_port: int = 18444
    tls_cert: Path = Path("certs/gateway.crt")
    tls_key: Path = Path("certs/gateway.key")
    database: Path = Path("data/devcontrol.db")
    initial_pairing_code: str | None = None
    credential_ttl_seconds: int = 24 * 60 * 60
    admin_token: str = ""
    telemetry_interval_seconds: float = 2.0
    enable_background_tasks: bool = True
    mqtt_enabled: bool = False
    mqtt_host: str = ""
    mqtt_port: int = 8883
    mqtt_ca: Path = Path("certs/demo-ca.crt")
    mqtt_client_cert: Path | None = None
    mqtt_client_key: Path | None = None
    mqtt_username: str = ""
    mqtt_password: str = ""
    mqtt_topic_prefix: str = "devcontrol/v1"
    max_transport_message_bytes: int = 64 * 1024

    @classmethod
    def from_env(cls) -> "GatewayConfig":
        return cls(
            host=os.getenv("DEVCONTROL_HOST", "0.0.0.0"),
            port=int(os.getenv("DEVCONTROL_PORT", "8443")),
            admin_host="127.0.0.1",
            admin_port=int(os.getenv("DEVCONTROL_ADMIN_PORT", "18444")),
            tls_cert=Path(os.getenv("DEVCONTROL_TLS_CERT", "certs/gateway.crt")),
            tls_key=Path(os.getenv("DEVCONTROL_TLS_KEY", "certs/gateway.key")),
            database=Path(os.getenv("DEVCONTROL_DATABASE", "data/devcontrol.db")),
            initial_pairing_code=os.getenv("DEVCONTROL_INITIAL_PAIRING_CODE"),
            credential_ttl_seconds=int(
                os.getenv("DEVCONTROL_CREDENTIAL_TTL_SECONDS", "86400")
            ),
            admin_token=os.getenv("DEVCONTROL_ADMIN_TOKEN", secrets.token_urlsafe(24)),
            telemetry_interval_seconds=float(
                os.getenv("DEVCONTROL_TELEMETRY_INTERVAL", "2")
            ),
            mqtt_enabled=os.getenv(
                "DEVCONTROL_MQTT_ENABLED", "false"
            ).lower() in {"1", "true", "yes"},
            mqtt_host=os.getenv("DEVCONTROL_MQTT_HOST", ""),
            mqtt_port=int(os.getenv("DEVCONTROL_MQTT_PORT", "8883")),
            mqtt_ca=Path(
                os.getenv("DEVCONTROL_MQTT_CA", "certs/demo-ca.crt")
            ),
            mqtt_client_cert=_optional_path(
                os.getenv("DEVCONTROL_MQTT_CLIENT_CERT")
            ),
            mqtt_client_key=_optional_path(
                os.getenv("DEVCONTROL_MQTT_CLIENT_KEY")
            ),
            mqtt_username=os.getenv("DEVCONTROL_MQTT_USERNAME", ""),
            mqtt_password=os.getenv("DEVCONTROL_MQTT_PASSWORD", ""),
            mqtt_topic_prefix=os.getenv(
                "DEVCONTROL_MQTT_TOPIC_PREFIX", "devcontrol/v1"
            ),
            max_transport_message_bytes=int(
                os.getenv("DEVCONTROL_MAX_TRANSPORT_MESSAGE_BYTES", "65536")
            ),
        )

    def validate(self) -> None:
        if self.credential_ttl_seconds <= 0:
            raise ValueError("Credential lifetime must be positive")
        if not 1024 <= self.max_transport_message_bytes <= 1024 * 1024:
            raise ValueError(
                "Transport message limit must be between 1 KiB and 1 MiB"
            )
        if not self.mqtt_enabled:
            return
        if not self.mqtt_host.strip():
            raise ValueError("MQTT host is required when MQTT is enabled")
        if not 1 <= self.mqtt_port <= 65535:
            raise ValueError("MQTT port must be between 1 and 65535")
        if not self.mqtt_ca.is_file():
            raise ValueError("MQTT broker CA certificate does not exist")
        if (self.mqtt_client_cert is None) != (self.mqtt_client_key is None):
            raise ValueError(
                "MQTT client certificate and key must be configured together"
            )
        uses_mtls = (
            self.mqtt_client_cert is not None
            and self.mqtt_client_key is not None
        )
        if uses_mtls:
            assert self.mqtt_client_cert is not None
            assert self.mqtt_client_key is not None
            if not self.mqtt_client_cert.is_file():
                raise ValueError("MQTT client certificate does not exist")
            if not self.mqtt_client_key.is_file():
                raise ValueError("MQTT client key does not exist")
        uses_password = bool(self.mqtt_username and self.mqtt_password)
        if not uses_mtls and not uses_password:
            raise ValueError(
                "MQTT requires mTLS or a non-empty username/password pair"
            )
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_/-]{0,126}", self.mqtt_topic_prefix):
            raise ValueError("MQTT topic prefix contains unsafe characters")
        if self.mqtt_topic_prefix.endswith("/") or "//" in self.mqtt_topic_prefix:
            raise ValueError("MQTT topic prefix must not contain empty levels")
