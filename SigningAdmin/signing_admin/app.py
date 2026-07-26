"""Loopback-only FastAPI application for certificate-signing administration."""

from __future__ import annotations

import argparse
import secrets
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from pydantic import BaseModel, Field
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from .service import SigningAdminError, SigningAdminService


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: object) -> Response:
        response = await call_next(request)  # type: ignore[operator]
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; "
            "base-uri 'none'; frame-ancestors 'none'"
        )
        return response


class InitializeRequest(BaseModel):
    issuerRoot: str = Field(min_length=1)
    appCaPath: str = Field(min_length=1)
    commonName: str = "DevControl Project Gateway CA"
    validDays: int = 3650
    caKeyPassword: str = Field(min_length=1)
    overwrite: bool = False


class SignRequest(BaseModel):
    csrPath: str = Field(min_length=1)
    caCertificatePath: str = Field(min_length=1)
    caPrivateKeyPath: str = Field(min_length=1)
    caKeyPassword: str = Field(min_length=1)
    outputPath: str = Field(min_length=1)
    validDays: int = 90
    overwrite: bool = False


class RotationStageRequest(BaseModel):
    existingTrustPath: str = Field(min_length=1)
    newCaPath: str = Field(min_length=1)
    appCaPath: str = Field(min_length=1)
    overwrite: bool = False


class RotationFinalizeRequest(BaseModel):
    newCaPath: str = Field(min_length=1)
    appCaPath: str = Field(min_length=1)
    overwrite: bool = False


class InspectRequest(BaseModel):
    path: str = Field(min_length=1)


def _console_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _default_workspace_root() -> Path:
    return _console_root().parent


def create_app(workspace_root: Path | None = None) -> FastAPI:
    service = SigningAdminService(workspace_root or _default_workspace_root())
    app = FastAPI(
        title="DevControl Signing Admin",
        version="1.0.0",
        docs_url=None,
        redoc_url=None,
    )
    app.add_middleware(SecurityHeadersMiddleware)
    app.state.downloads: dict[str, Path] = {}

    @app.exception_handler(SigningAdminError)
    async def signing_error_handler(_: Request, exc: SigningAdminError) -> JSONResponse:
        return JSONResponse(status_code=400, content={"error": exc.args[0]})

    @app.get("/", response_class=HTMLResponse)
    async def dashboard() -> HTMLResponse:
        page = Path(__file__).resolve().parent / "static" / "index.html"
        return HTMLResponse(page.read_text("utf-8"))

    @app.get("/api/v1/health")
    async def health() -> dict[str, str]:
        return {"status": "ok", "service": "devcontrol-signing-admin"}

    @app.post("/api/v1/project-ca")
    async def initialize_project_ca(body: InitializeRequest) -> dict[str, object]:
        return service.initialize_project_ca(
            issuer_root=body.issuerRoot,
            app_ca_path=body.appCaPath,
            common_name=body.commonName,
            valid_days=body.validDays,
            password=body.caKeyPassword,
            overwrite=body.overwrite,
        )

    @app.post("/api/v1/gateway-certificates")
    async def sign_gateway_certificate(body: SignRequest) -> dict[str, object]:
        certificate = service.sign_gateway_csr(
            csr_path=body.csrPath,
            ca_certificate_path=body.caCertificatePath,
            ca_private_key_path=body.caPrivateKeyPath,
            password=body.caKeyPassword,
            output_path=body.outputPath,
            valid_days=body.validDays,
            overwrite=body.overwrite,
        )
        download_id = secrets.token_urlsafe(24)
        app.state.downloads[download_id] = certificate.path
        return {
            "certificate": certificate.as_dict(),
            "downloadUrl": f"/api/v1/downloads/{download_id}",
            "message": "Gateway certificate issued. Send only gateway.crt to the gateway owner.",
        }

    @app.get("/api/v1/downloads/{download_id}")
    async def download_gateway_certificate(download_id: str) -> FileResponse:
        path = app.state.downloads.get(download_id)
        if path is None or not path.is_file():
            raise HTTPException(status_code=404, detail="Download is unavailable")
        return FileResponse(path, media_type="application/x-pem-file", filename="gateway.crt")

    @app.post("/api/v1/root-ca/transition")
    async def stage_root_ca_rotation(body: RotationStageRequest) -> dict[str, object]:
        return service.stage_root_ca_rotation(
            existing_trust_path=body.existingTrustPath,
            new_ca_path=body.newCaPath,
            app_ca_path=body.appCaPath,
            overwrite=body.overwrite,
        )

    @app.post("/api/v1/root-ca/finalize")
    async def finalize_root_ca_rotation(body: RotationFinalizeRequest) -> dict[str, object]:
        return service.finalize_root_ca_rotation(
            new_ca_path=body.newCaPath,
            app_ca_path=body.appCaPath,
            overwrite=body.overwrite,
        )

    @app.post("/api/v1/certificates/inspect")
    async def inspect_certificate(body: InspectRequest) -> dict[str, object]:
        return {"certificates": service.inspect_certificate(body.path)}

    return app


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Start the local-only DevControl signing administrator console."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18445)
    parser.add_argument("--workspace-root", type=Path, default=_default_workspace_root())
    args = parser.parse_args()
    if args.host not in {"127.0.0.1", "localhost", "::1"}:
        parser.error("Signing Admin must listen on loopback only")
    uvicorn.run(create_app(args.workspace_root), host=args.host, port=args.port)


if __name__ == "__main__":
    main()
