"""Certificate issuer workflows kept outside the gateway runtime.

The caller supplies all filesystem paths.  The accompanying web console is
loopback-only; this module neither stores passwords nor copies private keys.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


_PEM_CERTIFICATE = re.compile(
    rb"-----BEGIN CERTIFICATE-----\s+.*?-----END CERTIFICATE-----\s*",
    re.DOTALL,
)
_MAX_GATEWAY_SANS = 16


class SigningAdminError(ValueError):
    """A request is unsafe or cannot complete its certificate workflow."""


@dataclass(frozen=True)
class CertificateDetails:
    path: Path
    subject: str
    issuer: str
    serial_number: str
    expires_at: str
    sans: list[str]

    def as_dict(self) -> dict[str, object]:
        return {
            "path": str(self.path),
            "subject": self.subject,
            "issuer": self.issuer,
            "serialNumber": self.serial_number,
            "expiresAt": self.expires_at,
            "subjectAlternativeNames": self.sans,
        }


def _normalise(path: str | Path, base_dir: Path) -> Path:
    candidate = Path(path).expanduser()
    if not candidate.is_absolute():
        candidate = base_dir / candidate
    return candidate.resolve(strict=False)


def _is_within(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
    except ValueError:
        return False
    return True


def _require_existing_file(path: Path, description: str) -> None:
    if not path.is_file():
        raise SigningAdminError(f"{description} does not exist or is not a file: {path}")


def _require_output_available(path: Path, overwrite: bool) -> None:
    if path.exists() and not overwrite:
        raise SigningAdminError(
            f"Refusing to overwrite existing file: {path}. Confirm overwrite first."
        )
    if path.exists() and path.is_dir():
        raise SigningAdminError(f"Output path is a directory: {path}")


def _password_bytes(password: str) -> bytes:
    if not password:
        raise SigningAdminError("CA private-key password must not be empty")
    return password.encode("utf-8")


def _read_certificate_bundle(path: Path) -> list[x509.Certificate]:
    _require_existing_file(path, "Certificate file")
    blocks = _PEM_CERTIFICATE.findall(path.read_bytes())
    if not blocks:
        raise SigningAdminError(f"No PEM certificate was found in: {path}")
    try:
        return [x509.load_pem_x509_certificate(block) for block in blocks]
    except ValueError as error:
        raise SigningAdminError(f"Invalid PEM certificate in: {path}") from error


def _pem_bundle(certificates: list[x509.Certificate]) -> bytes:
    seen: set[bytes] = set()
    encoded: list[bytes] = []
    for certificate in certificates:
        fingerprint = certificate.fingerprint(hashes.SHA256())
        if fingerprint not in seen:
            seen.add(fingerprint)
            encoded.append(certificate.public_bytes(serialization.Encoding.PEM))
    if not encoded:
        raise SigningAdminError("At least one public CA certificate is required")
    return b"".join(encoded)


def _subject_alternative_names(certificate: x509.Certificate) -> list[str]:
    try:
        extension = certificate.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        ).value
    except x509.ExtensionNotFound:
        return []
    names: list[str] = []
    names.extend(extension.get_values_for_type(x509.DNSName))
    names.extend(str(value) for value in extension.get_values_for_type(x509.IPAddress))
    return names


def _details(path: Path, certificate: x509.Certificate) -> CertificateDetails:
    return CertificateDetails(
        path=path,
        subject=certificate.subject.rfc4514_string(),
        issuer=certificate.issuer.rfc4514_string(),
        serial_number=format(certificate.serial_number, "X"),
        expires_at=certificate.not_valid_after_utc.isoformat(),
        sans=_subject_alternative_names(certificate),
    )


def _require_ca_certificate(certificate: x509.Certificate, description: str) -> None:
    try:
        constraints = certificate.extensions.get_extension_for_class(
            x509.BasicConstraints
        ).value
    except x509.ExtensionNotFound as error:
        raise SigningAdminError(f"{description} is missing BasicConstraints") from error
    if not constraints.ca:
        raise SigningAdminError(f"{description} is not a CA certificate")
    try:
        usage = certificate.extensions.get_extension_for_class(x509.KeyUsage).value
    except x509.ExtensionNotFound as error:
        raise SigningAdminError(f"{description} is missing KeyUsage") from error
    if not usage.key_cert_sign:
        raise SigningAdminError(f"{description} cannot sign certificates")


def _gateway_san(csr: x509.CertificateSigningRequest) -> x509.SubjectAlternativeName:
    try:
        san = csr.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    except x509.ExtensionNotFound as error:
        raise SigningAdminError("CSR must contain at least one DNS or IP SAN") from error
    entries = list(san)
    if not entries or len(entries) > _MAX_GATEWAY_SANS:
        raise SigningAdminError(
            f"CSR must contain between 1 and {_MAX_GATEWAY_SANS} DNS or IP SANs"
        )
    if any(not isinstance(entry, (x509.DNSName, x509.IPAddress)) for entry in entries):
        raise SigningAdminError("CSR SANs may contain DNS names and IP addresses only")
    return san


def _require_p256_public_key(public_key: object, description: str) -> None:
    if not isinstance(public_key, ec.EllipticCurvePublicKey) or not isinstance(
        public_key.curve, ec.SECP256R1
    ):
        raise SigningAdminError(f"{description} must use an ECDSA P-256 public key")


class SigningAdminService:
    """Creates project CAs, signs approved gateway CSRs, and rotates roots."""

    def __init__(self, workspace_root: Path) -> None:
        self.workspace_root = workspace_root.resolve(strict=False)

    def resolve_path(self, value: str | Path) -> Path:
        return _normalise(value, self.workspace_root)

    def initialize_project_ca(
        self,
        *,
        issuer_root: str,
        app_ca_path: str,
        common_name: str,
        valid_days: int,
        password: str,
        overwrite: bool,
    ) -> dict[str, object]:
        if not 365 <= valid_days <= 7300:
            raise SigningAdminError("CA validity must be between 365 and 7300 days")
        if not common_name.strip():
            raise SigningAdminError("Project CA common name must not be empty")

        issuer_directory = self.resolve_path(issuer_root)
        if _is_within(issuer_directory, self.workspace_root):
            raise SigningAdminError(
                "Issuer root must be outside this source workspace; choose a protected directory."
            )
        target_app_ca = self.resolve_path(app_ca_path)
        certificate_path = issuer_directory / "project-ca.crt"
        private_key_path = issuer_directory / "project-ca.key"
        _require_output_available(certificate_path, overwrite)
        _require_output_available(private_key_path, overwrite)
        _require_output_available(target_app_ca, overwrite)

        issuer_directory.mkdir(parents=True, exist_ok=True)
        target_app_ca.parent.mkdir(parents=True, exist_ok=True)
        now = datetime.now(UTC)
        key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name.strip())])
        certificate = (
            x509.CertificateBuilder()
            .subject_name(name)
            .issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=5))
            .not_valid_after(now + timedelta(days=valid_days))
            .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
            .add_extension(
                x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False
            )
            .add_extension(
                x509.AuthorityKeyIdentifier.from_issuer_public_key(key.public_key()),
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
            .sign(key, hashes.SHA256())
        )
        certificate_pem = certificate.public_bytes(serialization.Encoding.PEM)
        certificate_path.write_bytes(certificate_pem)
        private_key_path.write_bytes(
            key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.BestAvailableEncryption(_password_bytes(password)),
            )
        )
        target_app_ca.write_bytes(certificate_pem)
        return {
            "issuerRoot": str(issuer_directory),
            "caCertificate": _details(certificate_path, certificate).as_dict(),
            "appCaPath": str(target_app_ca),
            "message": "Project CA created and its public certificate was deployed to the App trust path.",
        }

    def sign_gateway_csr(
        self,
        *,
        csr_path: str,
        ca_certificate_path: str,
        ca_private_key_path: str,
        password: str,
        output_path: str,
        valid_days: int,
        overwrite: bool,
    ) -> CertificateDetails:
        if not 1 <= valid_days <= 397:
            raise SigningAdminError("Gateway certificate validity must be between 1 and 397 days")

        csr_file = self.resolve_path(csr_path)
        ca_certificate_file = self.resolve_path(ca_certificate_path)
        ca_private_key_file = self.resolve_path(ca_private_key_path)
        output_file = self.resolve_path(output_path)
        _require_existing_file(csr_file, "Gateway CSR")
        _require_existing_file(ca_certificate_file, "Project CA certificate")
        _require_existing_file(ca_private_key_file, "Project CA private key")
        _require_output_available(output_file, overwrite)
        try:
            csr = x509.load_pem_x509_csr(csr_file.read_bytes())
        except ValueError as error:
            raise SigningAdminError(f"Invalid PEM CSR: {csr_file}") from error
        if not csr.is_signature_valid:
            raise SigningAdminError("CSR signature is invalid")
        _require_p256_public_key(csr.public_key(), "Gateway CSR")
        san = _gateway_san(csr)

        certificates = _read_certificate_bundle(ca_certificate_file)
        if len(certificates) != 1:
            raise SigningAdminError("CA certificate path must contain exactly one certificate")
        ca_certificate = certificates[0]
        _require_ca_certificate(ca_certificate, "Project CA certificate")
        try:
            ca_private_key = serialization.load_pem_private_key(
                ca_private_key_file.read_bytes(), password=_password_bytes(password)
            )
        except (TypeError, ValueError) as error:
            raise SigningAdminError("Unable to unlock the project CA private key") from error
        if not isinstance(ca_private_key, ec.EllipticCurvePrivateKey) or not isinstance(
            ca_private_key.curve, ec.SECP256R1
        ):
            raise SigningAdminError("Project CA private key must be an ECDSA P-256 key")
        if (
            ca_certificate.public_key().public_bytes(
                serialization.Encoding.DER,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            )
            != ca_private_key.public_key().public_bytes(
                serialization.Encoding.DER,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            )
        ):
            raise SigningAdminError("CA certificate does not match the supplied private key")

        now = datetime.now(UTC)
        expires_at = min(now + timedelta(days=valid_days), ca_certificate.not_valid_after_utc)
        if expires_at <= now:
            raise SigningAdminError("Project CA certificate has already expired")
        certificate = (
            x509.CertificateBuilder()
            .subject_name(csr.subject)
            .issuer_name(ca_certificate.subject)
            .public_key(csr.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=5))
            .not_valid_after(expires_at)
            .add_extension(san, critical=False)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(
                x509.SubjectKeyIdentifier.from_public_key(csr.public_key()), critical=False
            )
            .add_extension(
                x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_certificate.public_key()),
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
                x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False
            )
            .sign(ca_private_key, hashes.SHA256())
        )
        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
        return _details(output_file, certificate)

    def stage_root_ca_rotation(
        self,
        *,
        existing_trust_path: str,
        new_ca_path: str,
        app_ca_path: str,
        overwrite: bool,
    ) -> dict[str, object]:
        existing_file = self.resolve_path(existing_trust_path)
        new_ca_file = self.resolve_path(new_ca_path)
        target_file = self.resolve_path(app_ca_path)
        _require_output_available(target_file, overwrite)
        existing_certificates = _read_certificate_bundle(existing_file)
        new_certificates = _read_certificate_bundle(new_ca_file)
        for certificate in [*existing_certificates, *new_certificates]:
            _require_ca_certificate(certificate, "Root CA certificate")
        target_file.parent.mkdir(parents=True, exist_ok=True)
        bundle = _pem_bundle([*existing_certificates, *new_certificates])
        target_file.write_bytes(bundle)
        return {
            "appCaPath": str(target_file),
            "certificateCount": len(_read_certificate_bundle(target_file)),
            "message": (
                "Transition trust bundle deployed. Release the App, renew gateway certificates "
                "under the new CA, and only then retire the old root."
            ),
        }

    def finalize_root_ca_rotation(
        self, *, new_ca_path: str, app_ca_path: str, overwrite: bool
    ) -> dict[str, object]:
        new_ca_file = self.resolve_path(new_ca_path)
        target_file = self.resolve_path(app_ca_path)
        _require_output_available(target_file, overwrite)
        new_certificates = _read_certificate_bundle(new_ca_file)
        for certificate in new_certificates:
            _require_ca_certificate(certificate, "New root CA certificate")
        target_file.parent.mkdir(parents=True, exist_ok=True)
        target_file.write_bytes(_pem_bundle(new_certificates))
        return {
            "appCaPath": str(target_file),
            "certificateCount": len(new_certificates),
            "message": "Old root removed from App trust path. Confirm all deployed gateways use the new CA.",
        }

    def inspect_certificate(self, path: str) -> list[dict[str, object]]:
        certificate_path = self.resolve_path(path)
        return [
            _details(certificate_path, certificate).as_dict()
            for certificate in _read_certificate_bundle(certificate_path)
        ]
