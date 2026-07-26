"""Non-interactive entry points for controlled certificate automation."""

from __future__ import annotations

import argparse
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

from .service import SigningAdminError, SigningAdminService


def _password_from_environment(name: str) -> str:
    password = os.getenv(name)
    if not password:
        raise SigningAdminError(f"environment variable {name} is not set or is empty")
    return password


def _create_project_ca(
    certificate_path: Path,
    private_key_path: Path,
    common_name: str,
    valid_days: int,
    password: str,
    overwrite: bool,
) -> None:
    if not 365 <= valid_days <= 7300:
        raise SigningAdminError("--valid-days must be between 365 and 7300")
    existing = [path for path in (certificate_path, private_key_path) if path.exists()]
    if existing and not overwrite:
        raise SigningAdminError("refusing to overwrite existing file(s): " + ", ".join(map(str, existing)))
    certificate_path.parent.mkdir(parents=True, exist_ok=True)
    private_key_path.parent.mkdir(parents=True, exist_ok=True)
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    now = datetime.now(UTC)
    certificate = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=valid_days))
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(key.public_key()), critical=False
        )
        .add_extension(
            x509.KeyUsage(
                digital_signature=True, content_commitment=False, key_encipherment=False,
                data_encipherment=False, key_agreement=False, key_cert_sign=True,
                crl_sign=True, encipher_only=False, decipher_only=False,
            ),
            critical=True,
        )
        .sign(key, hashes.SHA256())
    )
    certificate_path.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    private_key_path.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.BestAvailableEncryption(password.encode("utf-8")),
        )
    )
    print(f"Created project CA certificate: {certificate_path.resolve()}")
    print(f"Created protected project CA key: {private_key_path.resolve()}")


def main() -> None:
    parser = argparse.ArgumentParser(description="DevControl certificate issuer automation")
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create", help="create a protected project CA")
    create.add_argument("--cert", required=True, type=Path)
    create.add_argument("--key", required=True, type=Path)
    create.add_argument("--common-name", default="DevControl Project Gateway CA")
    create.add_argument("--valid-days", type=int, default=3650)
    create.add_argument("--key-password-env", required=True)
    create.add_argument("--force", action="store_true")
    sign = commands.add_parser("sign", help="sign an approved gateway CSR")
    sign.add_argument("--csr", required=True, type=Path)
    sign.add_argument("--ca-cert", required=True, type=Path)
    sign.add_argument("--ca-key", required=True, type=Path)
    sign.add_argument("--ca-key-password-env", required=True)
    sign.add_argument("--output", type=Path, default=Path("gateway.crt"))
    sign.add_argument("--valid-days", type=int, default=90)
    sign.add_argument("--force", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "create":
            _create_project_ca(
                args.cert, args.key, args.common_name, args.valid_days,
                _password_from_environment(args.key_password_env), args.force,
            )
            return
        certificate = SigningAdminService(Path.cwd()).sign_gateway_csr(
            csr_path=str(args.csr), ca_certificate_path=str(args.ca_cert),
            ca_private_key_path=str(args.ca_key),
            password=_password_from_environment(args.ca_key_password_env),
            output_path=str(args.output), valid_days=args.valid_days, overwrite=args.force,
        )
        print(f"Issued gateway certificate: {certificate.path}")
        print(f"Certificate SANs: {', '.join(certificate.sans)}")
        print(f"Certificate expires: {certificate.expires_at}")
    except SigningAdminError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
