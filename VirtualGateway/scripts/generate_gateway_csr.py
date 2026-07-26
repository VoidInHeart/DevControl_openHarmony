"""Create a gateway private key and certificate-signing request (CSR).

The gateway owner runs this locally and sends only the CSR to the project
issuer.  The generated private key remains on this gateway machine.
"""

from __future__ import annotations

import argparse
import ipaddress
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


def write_private_key(path: Path, key: ec.EllipticCurvePrivateKey) -> None:
    path.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )


def existing_path_guard(paths: list[Path], force: bool) -> None:
    if force:
        return
    existing = [str(path) for path in paths if path.exists()]
    if existing:
        raise SystemExit(
            "Refusing to overwrite existing file(s): "
            + ", ".join(existing)
            + ". Use --force to replace them."
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a DevControl gateway key and CSR for central CA signing."
    )
    parser.add_argument("--host", action="append", default=[], help="DNS SAN; repeat as needed")
    parser.add_argument("--ip", action="append", default=[], help="IP SAN; repeat as needed")
    parser.add_argument("--key", type=Path, default=Path("certs/gateway.key"))
    parser.add_argument("--csr", type=Path, default=Path("certs/gateway.csr"))
    parser.add_argument("--force", action="store_true", help="replace existing key or CSR")
    args = parser.parse_args()

    hosts = list(dict.fromkeys(args.host))
    ips = list(dict.fromkeys(args.ip))
    if not hosts and not ips:
        parser.error("at least one --host or --ip is required")
    try:
        san_entries: list[x509.GeneralName] = [x509.DNSName(host) for host in hosts]
        san_entries.extend(x509.IPAddress(ipaddress.ip_address(value)) for value in ips)
    except ValueError as error:
        parser.error(f"invalid IP address: {error}")

    existing_path_guard([args.key, args.csr], args.force)
    args.key.parent.mkdir(parents=True, exist_ok=True)
    args.csr.parent.mkdir(parents=True, exist_ok=True)
    key = ec.generate_private_key(ec.SECP256R1())
    common_name = hosts[0] if hosts else ips[0]
    request = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)]))
        .add_extension(x509.SubjectAlternativeName(san_entries), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
        .sign(key, hashes.SHA256())
    )
    write_private_key(args.key, key)
    args.csr.write_bytes(request.public_bytes(serialization.Encoding.PEM))
    print(f"Generated gateway private key: {args.key.resolve()}")
    print(f"Generated gateway CSR: {args.csr.resolve()}")
    print("Send only the CSR to the project certificate issuer; never share the private key.")


if __name__ == "__main__":
    main()
