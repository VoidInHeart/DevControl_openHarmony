from __future__ import annotations

import sys

import uvicorn

from .api import create_app
from .config import GatewayConfig


def main() -> int:
    config = GatewayConfig.from_environment()
    if not config.certificate_path.is_file() or not config.private_key_path.is_file():
        print(
            "TLS certificate or private key is missing. Set DEVCONTROL_TLS_CERT and "
            "DEVCONTROL_TLS_KEY; insecure HTTP fallback is intentionally disabled.",
            file=sys.stderr,
        )
        return 2
    uvicorn.run(
        create_app(config),
        host=config.host,
        port=config.port,
        ssl_certfile=str(config.certificate_path),
        ssl_keyfile=str(config.private_key_path),
        log_level="info",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
