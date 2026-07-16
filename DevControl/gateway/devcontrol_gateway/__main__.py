from __future__ import annotations

import asyncio
import logging

import uvicorn

from .app import create_admin_app, create_app
from .config import GatewayConfig
from .service import GatewayService


async def run() -> None:
    config = GatewayConfig.from_env()
    if not config.tls_cert.is_file() or not config.tls_key.is_file():
        raise SystemExit(
            "TLS certificate/key missing. Set DEVCONTROL_TLS_CERT and "
            "DEVCONTROL_TLS_KEY; plaintext fallback is intentionally disabled."
        )

    service = GatewayService(config)
    business_app = create_app(config, service)
    admin_app = create_admin_app(service, config.admin_token)
    logging.warning(
        "DevControl pairing code: %s (valid for %ss)",
        service.sessions.pairing_code,
        service.sessions.pairing_expires_in,
    )
    logging.warning(
        "Local maintenance endpoint: http://127.0.0.1:%s "
        "(X-Admin-Token printed once): %s",
        config.admin_port,
        config.admin_token,
    )

    business = uvicorn.Server(
        uvicorn.Config(
            business_app,
            host=config.host,
            port=config.port,
            ssl_certfile=str(config.tls_cert),
            ssl_keyfile=str(config.tls_key),
            log_level="info",
        )
    )
    admin = uvicorn.Server(
        uvicorn.Config(
            admin_app,
            host="127.0.0.1",
            port=config.admin_port,
            log_level="warning",
        )
    )
    await asyncio.gather(business.serve(), admin.serve())


def main() -> None:
    asyncio.run(run())


if __name__ == "__main__":
    main()

