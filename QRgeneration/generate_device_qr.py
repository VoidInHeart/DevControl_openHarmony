#!/usr/bin/env python3
"""Create a persistent DevControl device-registration QR image without handling private keys.

The signed device identity certificate must be produced by the gateway provisioning
service. This tool only packages that certificate with the public declaration.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

try:
    import qrcode
    from qrcode.constants import ERROR_CORRECT_M
except ImportError as exc:
    raise SystemExit(
        "Missing dependency: run `python -m pip install -r requirements.txt`."
    ) from exc


IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9._-]{0,63}$")
DEVICE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{2,63}$")
COMPACT_JWS_PATTERN = re.compile(
    r"^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$"
)
DEVICE_NAME_PATTERN = re.compile(r"^[^\x00-\x1F\x7F]{1,64}$")
MAX_QR_PAYLOAD_LENGTH = 8192


def identifier(value: str, field: str) -> str:
    if not IDENTIFIER_PATTERN.fullmatch(value):
        raise ValueError(f"{field} must match {IDENTIFIER_PATTERN.pattern}")
    return value


def device_id(value: str) -> str:
    if not DEVICE_ID_PATTERN.fullmatch(value):
        raise ValueError(f"device-id must match {DEVICE_ID_PATTERN.pattern}")
    return value


def device_name(value: str) -> str:
    if not DEVICE_NAME_PATTERN.fullmatch(value) or not value.strip():
        raise ValueError(
            "device-name must be 1-64 non-control characters and cannot be blank"
        )
    return value


def capabilities(value: str) -> list[str]:
    values = [item.strip() for item in value.split(",") if item.strip()]
    if not 1 <= len(values) <= 32:
        raise ValueError("capabilities must contain between 1 and 32 identifiers")
    if len(values) != len(set(values)):
        raise ValueError("capabilities must not contain duplicates")
    return [identifier(item, "capability") for item in values]


def compact_jws(value: str) -> str:
    if len(value) > 4096 or not COMPACT_JWS_PATTERN.fullmatch(value):
        raise ValueError("gateway-proof must be a compact JWS with three base64url segments")
    return value


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a signed-device-registration QR code for DevControl."
    )
    parser.add_argument("--device-id", required=True, help="Immutable device serial number")
    parser.add_argument("--device-name", required=True, help="Human-readable device display name")
    parser.add_argument("--device-type", required=True, help="Device adapter type, e.g. curtain")
    parser.add_argument("--category-id", required=True, help="DevControl feature category, e.g. curtains")
    parser.add_argument(
        "--capabilities",
        required=True,
        help="Comma-separated command capability ids, e.g. setPosition,stop",
    )
    parser.add_argument(
        "--gateway-proof",
        help="Existing static device-certificate JWS (normally use the provisioning API)",
    )
    parser.add_argument(
        "--admin-url",
        default="http://127.0.0.1:18444/admin/v1/devices/provision",
        help="Loopback VirtualGateway provisioning endpoint",
    )
    parser.add_argument(
        "--admin-token",
        help="X-Admin-Token printed when VirtualGateway starts; never stored in the QR",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="PNG destination (defaults to deviceQR/device-<serial>.png)",
    )
    parser.add_argument(
        "--uri-wrapper",
        action="store_true",
        help="Encode the JSON in devcontrol://register?payload=... instead of raw JSON",
    )
    parser.add_argument(
        "--payload-output",
        type=Path,
        help="Optional UTF-8 file to write the exact QR payload",
    )
    return parser.parse_args()


def issue_gateway_proof(
    args: argparse.Namespace, declaration: dict[str, object]
) -> str:
    if args.gateway_proof:
        return compact_jws(args.gateway_proof)
    if not args.admin_token:
        raise ValueError(
            "admin-token is required when gateway-proof is not supplied; "
            "start VirtualGateway and use its printed X-Admin-Token"
        )
    if not (
        args.admin_url.startswith("http://127.0.0.1:")
        or args.admin_url.startswith("http://localhost:")
        or args.admin_url.startswith("https://")
    ):
        raise ValueError("admin-url must be loopback HTTP or HTTPS")
    body = json.dumps(declaration, ensure_ascii=False, separators=(",", ":")).encode(
        "utf-8"
    )
    request = Request(
        args.admin_url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Admin-Token": args.admin_token,
        },
    )
    try:
        with urlopen(request, timeout=5) as response:
            raw = response.read().decode("utf-8")
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise ValueError(f"gateway provisioning failed ({exc.code}): {detail}") from exc
    except URLError as exc:
        raise ValueError(f"gateway provisioning is unavailable: {exc.reason}") from exc
    try:
        reply = json.loads(raw)
        proof = reply["gatewayProof"]
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        raise ValueError("gateway provisioning returned no valid gatewayProof") from exc
    if not isinstance(proof, str):
        raise ValueError("gateway provisioning returned a non-string gatewayProof")
    return compact_jws(proof)


def main() -> int:
    args = arguments()
    try:
        declaration = {
            "schema": "devcontrol.device-registration",
            "protocolVersion": "1.0",
            "deviceId": device_id(args.device_id),
            "deviceName": device_name(args.device_name),
            "deviceType": identifier(args.device_type, "device-type"),
            "categoryId": identifier(args.category_id, "category-id"),
            "capabilities": capabilities(args.capabilities),
        }
        proof_declaration = {
            key: value for key, value in declaration.items() if key != "schema"
        }
        manifest = {
            **declaration,
            "gatewayProofFormat": "jws",
            "gatewayProof": issue_gateway_proof(args, proof_declaration),
        }
    except ValueError as exc:
        print(f"Invalid registration declaration: {exc}", file=sys.stderr)
        return 2

    payload = json.dumps(manifest, ensure_ascii=True, separators=(",", ":"))
    if args.uri_wrapper:
        payload = "devcontrol://register?payload=" + quote(payload, safe="")
    if len(payload) > MAX_QR_PAYLOAD_LENGTH:
        print("QR payload exceeds the App's 8192-character safety limit.", file=sys.stderr)
        return 2

    output = args.output or (
        Path(__file__).with_name("deviceQR") / f"device-{manifest['deviceId']}.png"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    qr = qrcode.QRCode(
        version=None,
        error_correction=ERROR_CORRECT_M,
        box_size=10,
        border=4,
    )
    qr.add_data(payload)
    qr.make(fit=True)
    qr.make_image(fill_color="black", back_color="white").save(output)

    if args.payload_output:
        args.payload_output.parent.mkdir(parents=True, exist_ok=True)
        args.payload_output.write_text(payload, encoding="utf-8")

    print(f"Created {output.resolve()}")
    print(f"QR payload length: {len(payload)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
