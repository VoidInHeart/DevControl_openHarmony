from __future__ import annotations

import ipaddress
from pathlib import Path

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.x509.oid import NameOID

from signing_admin.service import SigningAdminError, SigningAdminService


def write_gateway_csr(path: Path, *, unsupported_san: bool = False, rsa_key: bool = False) -> None:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048) if rsa_key else ec.generate_private_key(ec.SECP256R1())
    san: list[x509.GeneralName] = [x509.DNSName("gateway.test"), x509.IPAddress(ipaddress.ip_address("192.0.2.8"))]
    if unsupported_san:
        san.append(x509.UniformResourceIdentifier("spiffe://gateway.test"))
    request = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "gateway.test")]))
        .add_extension(x509.SubjectAlternativeName(san), critical=False)
        .sign(key, hashes.SHA256())
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(request.public_bytes(serialization.Encoding.PEM))


def test_initialize_sign_and_rotate_project_ca(tmp_path: Path) -> None:
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    service = SigningAdminService(workspace)
    app_ca = workspace / "app" / "demo_ca.crt"
    old_issuer = tmp_path / "old-issuer"
    created = service.initialize_project_ca(
        issuer_root=str(old_issuer), app_ca_path=str(app_ca), common_name="Old DevControl CA",
        valid_days=365, password="test-password", overwrite=False,
    )
    assert Path(str(created["appCaPath"])).read_bytes() == (old_issuer / "project-ca.crt").read_bytes()
    csr = tmp_path / "incoming" / "gateway.csr"
    output = tmp_path / "outgoing" / "gateway.crt"
    write_gateway_csr(csr)
    issued = service.sign_gateway_csr(
        csr_path=str(csr), ca_certificate_path=str(old_issuer / "project-ca.crt"),
        ca_private_key_path=str(old_issuer / "project-ca.key"), password="test-password",
        output_path=str(output), valid_days=90, overwrite=False,
    )
    assert issued.sans == ["gateway.test", "192.0.2.8"]
    new_issuer = tmp_path / "new-issuer"
    service.initialize_project_ca(
        issuer_root=str(new_issuer), app_ca_path=str(workspace / "unused" / "new_demo_ca.crt"),
        common_name="New DevControl CA", valid_days=365, password="test-password", overwrite=False,
    )
    staged = service.stage_root_ca_rotation(
        existing_trust_path=str(app_ca), new_ca_path=str(new_issuer / "project-ca.crt"),
        app_ca_path=str(app_ca), overwrite=True,
    )
    assert staged["certificateCount"] == 2
    finalized = service.finalize_root_ca_rotation(
        new_ca_path=str(new_issuer / "project-ca.crt"), app_ca_path=str(app_ca), overwrite=True,
    )
    assert finalized["certificateCount"] == 1


def test_issuer_root_cannot_be_created_in_workspace(tmp_path: Path) -> None:
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    with pytest.raises(SigningAdminError, match="outside this source workspace"):
        SigningAdminService(workspace).initialize_project_ca(
            issuer_root=str(workspace / "issuer"), app_ca_path=str(workspace / "demo_ca.crt"),
            common_name="Rejected CA", valid_days=365, password="test-password", overwrite=False,
        )


@pytest.mark.parametrize("unsupported_san,rsa_key", [(True, False), (False, True)])
def test_signing_rejects_unsafe_gateway_csr(
    tmp_path: Path, unsupported_san: bool, rsa_key: bool
) -> None:
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    service = SigningAdminService(workspace)
    issuer = tmp_path / "issuer"
    service.initialize_project_ca(
        issuer_root=str(issuer), app_ca_path=str(workspace / "demo_ca.crt"),
        common_name="DevControl CA", valid_days=365, password="test-password", overwrite=False,
    )
    csr = tmp_path / "incoming" / "gateway.csr"
    write_gateway_csr(csr, unsupported_san=unsupported_san, rsa_key=rsa_key)
    with pytest.raises(SigningAdminError):
        service.sign_gateway_csr(
            csr_path=str(csr), ca_certificate_path=str(issuer / "project-ca.crt"),
            ca_private_key_path=str(issuer / "project-ca.key"), password="test-password",
            output_path=str(tmp_path / "gateway.crt"), valid_days=90, overwrite=False,
        )
