from __future__ import annotations

import asyncio
import logging
import ssl
from typing import Any

import uvicorn

from .app import create_admin_app, create_app
from .config import GatewayConfig
from .service import GatewayService


def _business_server_config(app: Any, config: GatewayConfig) -> uvicorn.Config:
    server_config = uvicorn.Config(
        app,
        host=config.host,
        port=config.port,
        ssl_certfile=str(config.tls_cert),
        ssl_keyfile=str(config.tls_key),
        ssl_version=ssl.PROTOCOL_TLS_SERVER,
        ssl_ciphers="ECDHE+AESGCM:ECDHE+CHACHA20",
        ws_max_size=config.max_transport_message_bytes,
        ws_per_message_deflate=False,
        proxy_headers=False,
        server_header=False,
        log_level="info",
    )
    server_config.load()
    if server_config.ssl is None:
        raise RuntimeError("Business server TLS context was not created")
    server_config.ssl.minimum_version = ssl.TLSVersion.TLSv1_2
    server_config.ssl.options |= ssl.OP_NO_COMPRESSION
    return server_config


async def run() -> None:
    config = GatewayConfig.from_env()
    config.validate()
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

    business = uvicorn.Server(_business_server_config(business_app, config))
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

