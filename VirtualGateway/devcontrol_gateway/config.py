from __future__ import annotations

import os
import secrets
from dataclasses import dataclass
from pathlib import Path


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
        )
