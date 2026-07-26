from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives.asymmetric import ec


GATEWAY_SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
SIGNING_ADMIN_ROOT = Path(__file__).resolve().parents[2] / "SigningAdmin"


def run_script(script: str, *arguments: str, environment: dict[str, str] | None = None) -> None:
    issuer_commands = {"create_project_ca.py": "create", "sign_gateway_csr.py": "sign"}
    command = (
        [sys.executable, "-m", "signing_admin.cli", issuer_commands[script], *arguments]
        if script in issuer_commands
        else [sys.executable, str(GATEWAY_SCRIPTS / script), *arguments]
    )
    subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, **(environment or {})},
        cwd=SIGNING_ADMIN_ROOT if script in issuer_commands else GATEWAY_SCRIPTS.parent,
    )


def test_project_ca_can_issue_gateway_certificate_from_csr(tmp_path: Path) -> None:
    ca_cert = tmp_path / "issuer" / "project-ca.crt"
    ca_key = tmp_path / "issuer" / "project-ca.key"
    gateway_key = tmp_path / "gateway" / "gateway.key"
    gateway_csr = tmp_path / "gateway" / "gateway.csr"
    gateway_cert = tmp_path / "gateway" / "gateway.crt"
    password_environment = {"TEST_PROJECT_CA_PASSWORD": "unit-test-only-password"}
    run_script(
        "create_project_ca.py", "--cert", str(ca_cert), "--key", str(ca_key),
        "--key-password-env", "TEST_PROJECT_CA_PASSWORD", environment=password_environment,
    )
    run_script(
        "generate_gateway_csr.py", "--host", "gateway-alice.local", "--ip", "192.168.1.8",
        "--key", str(gateway_key), "--csr", str(gateway_csr),
    )
    run_script(
        "sign_gateway_csr.py", "--csr", str(gateway_csr), "--ca-cert", str(ca_cert),
        "--ca-key", str(ca_key), "--ca-key-password-env", "TEST_PROJECT_CA_PASSWORD",
        "--output", str(gateway_cert), environment=password_environment,
    )
    root = x509.load_pem_x509_certificate(ca_cert.read_bytes())
    certificate = x509.load_pem_x509_certificate(gateway_cert.read_bytes())
    san = certificate.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    assert "gateway-alice.local" in san.get_values_for_type(x509.DNSName)
    assert "192.168.1.8" in [str(value) for value in san.get_values_for_type(x509.IPAddress)]
    assert certificate.issuer == root.subject
    root.public_key().verify(
        certificate.signature, certificate.tbs_certificate_bytes,
        ec.ECDSA(certificate.signature_hash_algorithm),
    )
