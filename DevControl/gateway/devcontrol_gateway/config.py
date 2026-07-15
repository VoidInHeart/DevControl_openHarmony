from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class GatewayConfig:
    host: str
    port: int
    database_path: Path
    certificate_path: Path
    private_key_path: Path
    pairing_ttl_seconds: int = 300
    credential_ttl_seconds: int = 86_400

    @classmethod
    def from_environment(cls) -> "GatewayConfig":
        gateway_root = Path(__file__).resolve().parents[1]
        return cls(
            host=os.getenv("DEVCONTROL_HOST", "0.0.0.0"),
            port=int(os.getenv("DEVCONTROL_PORT", "8443")),
            database_path=Path(os.getenv("DEVCONTROL_DATABASE", str(gateway_root / "data" / "gateway.db"))),
            certificate_path=Path(os.getenv("DEVCONTROL_TLS_CERT", str(gateway_root / "certs" / "gateway.crt"))),
            private_key_path=Path(os.getenv("DEVCONTROL_TLS_KEY", str(gateway_root / "certs" / "gateway.key"))),
        )
