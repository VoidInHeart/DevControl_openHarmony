from __future__ import annotations

import argparse
import ipaddress
from datetime import UTC, datetime, timedelta
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", action="append", default=["localhost"])
    parser.add_argument("--ip", action="append", default=["127.0.0.1"])
    parser.add_argument("--output", type=Path, default=Path("certs"))
    parser.add_argument(
        "--app-ca",
        type=Path,
        default=Path("../entry/src/main/resources/rawfile/demo_ca.crt"),
    )
    args = parser.parse_args()

    output: Path = args.output
    output.mkdir(parents=True, exist_ok=True)
    args.app_ca.parent.mkdir(parents=True, exist_ok=True)
    now = datetime.now(UTC)

    ca_key = ec.generate_private_key(ec.SECP256R1())
    ca_name = x509.Name(
        [x509.NameAttribute(NameOID.COMMON_NAME, "DevControl Demo CA")]
    )
    ca_cert = (
        x509.CertificateBuilder()
        .subject_name(ca_name)
        .issuer_name(ca_name)
        .public_key(ca_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=365))
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .add_extension(
            x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()),
            critical=False,
        )
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(
                ca_key.public_key()
            ),
            critical=False,
        )
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=True,
                crl_sign=True,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .sign(ca_key, hashes.SHA256())
    )

    gateway_key = ec.generate_private_key(ec.SECP256R1())
    gateway_name = x509.Name(
        [x509.NameAttribute(NameOID.COMMON_NAME, args.host[0])]
    )
    san_entries: list[x509.GeneralName] = [
        x509.DNSName(host) for host in dict.fromkeys(args.host)
    ]
    san_entries.extend(
        x509.IPAddress(ipaddress.ip_address(value))
        for value in dict.fromkeys(args.ip)
    )
    gateway_cert = (
        x509.CertificateBuilder()
        .subject_name(gateway_name)
        .issuer_name(ca_name)
        .public_key(gateway_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=90))
        .add_extension(x509.SubjectAlternativeName(san_entries), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.SubjectKeyIdentifier.from_public_key(
                gateway_key.public_key()
            ),
            critical=False,
        )
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(
                ca_key.public_key()
            ),
            critical=False,
        )
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=True,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),
            critical=False,
        )
        .sign(ca_key, hashes.SHA256())
    )

    ca_pem = ca_cert.public_bytes(serialization.Encoding.PEM)
    (output / "demo-ca.crt").write_bytes(ca_pem)
    args.app_ca.write_bytes(ca_pem)
    write_private_key(output / "demo-ca.key", ca_key)
    (output / "gateway.crt").write_bytes(
        gateway_cert.public_bytes(serialization.Encoding.PEM)
    )
    write_private_key(output / "gateway.key", gateway_key)
    print(f"Generated CA and gateway certificate in {output.resolve()}")
    print(f"Copied public demo CA to {args.app_ca.resolve()}")


if __name__ == "__main__":
    main()
