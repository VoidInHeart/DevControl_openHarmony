from __future__ import annotations

import argparse
import os
import secrets
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import httpx


GATEWAY_ROOT = Path(__file__).resolve().parents[1]
SIGNING_ADMIN_ROOT = GATEWAY_ROOT.parent / "SigningAdmin"
ADMIN_TOKEN = "devcontrol-local-admin"
TEST_CA_PASSWORD_ENV = "DEVCONTROL_E2E_CA_PASSWORD"


def wait_until_ready(process: subprocess.Popen[str], base_url: str, ca_file: Path) -> None:
    for _ in range(40):
        if process.poll() is not None:
            output = process.stdout.read() if process.stdout is not None else ""
            raise RuntimeError(
                f"Gateway exited before readiness with code {process.returncode}:\n{output}"
            )
        try:
            response = httpx.get(base_url + "/api/v1/health", verify=str(ca_file), timeout=1, trust_env=False)
            response.raise_for_status()
            return
        except httpx.HTTPError:
            time.sleep(0.25)
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)
    output = process.stdout.read() if process.stdout is not None else ""
    raise TimeoutError(f"Gateway did not become ready within 10 seconds:\n{output}")


def run_script(name: str, *arguments: str, environment: dict[str, str] | None = None) -> None:
    issuer_commands = {"create_project_ca.py": "create", "sign_gateway_csr.py": "sign"}
    command = (
        [sys.executable, "-m", "signing_admin.cli", issuer_commands[name], *arguments]
        if name in issuer_commands
        else [sys.executable, str(GATEWAY_ROOT / "scripts" / name), *arguments]
    )
    subprocess.run(
        command,
        cwd=SIGNING_ADMIN_ROOT if name in issuer_commands else GATEWAY_ROOT,
        check=True,
        env={
            **os.environ,
            "NO_PROXY": "localhost,127.0.0.1",
            "no_proxy": "localhost,127.0.0.1",
            **(environment or {}),
        },
    )


def get_pairing_code(admin_url: str) -> str:
    response = httpx.get(
        admin_url + "/admin/v1/pairing-code",
        headers={"X-Admin-Token": ADMIN_TOKEN}, timeout=2, trust_env=False,
    )
    response.raise_for_status()
    pairing_code = response.json()["pairingCode"]
    if not isinstance(pairing_code, str):
        raise TypeError("Maintenance endpoint returned a non-string pairing code")
    return pairing_code


def create_ephemeral_tls_material(directory: Path) -> tuple[Path, Path, Path]:
    issuer_dir = directory / "issuer"
    gateway_dir = directory / "gateway"
    ca_cert = issuer_dir / "test-ca.crt"
    ca_key = issuer_dir / "test-ca.key"
    gateway_key = gateway_dir / "gateway.key"
    gateway_csr = gateway_dir / "gateway.csr"
    gateway_cert = gateway_dir / "gateway.crt"
    certificate_environment = {TEST_CA_PASSWORD_ENV: secrets.token_urlsafe(32)}
    run_script(
        "create_project_ca.py", "--cert", str(ca_cert), "--key", str(ca_key),
        "--key-password-env", TEST_CA_PASSWORD_ENV, environment=certificate_environment,
    )
    run_script(
        "generate_gateway_csr.py", "--ip", "127.0.0.1", "--key", str(gateway_key),
        "--csr", str(gateway_csr), environment=certificate_environment,
    )
    run_script(
        "sign_gateway_csr.py", "--csr", str(gateway_csr), "--ca-cert", str(ca_cert),
        "--ca-key", str(ca_key), "--ca-key-password-env", TEST_CA_PASSWORD_ENV,
        "--output", str(gateway_cert), environment=certificate_environment,
    )
    return ca_cert, gateway_cert, gateway_key


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--performance-count", type=int, default=1000)
    parser.add_argument("--stability-seconds", type=int, default=0)
    parser.add_argument("--port", type=int, default=8443)
    parser.add_argument("--admin-port", type=int, default=18444)
    args = parser.parse_args()
    base_url = f"https://127.0.0.1:{args.port}"
    admin_url = f"http://127.0.0.1:{args.admin_port}"
    with tempfile.TemporaryDirectory(prefix="devcontrol-e2e-") as temporary_directory:
        ca_file, gateway_cert, gateway_key = create_ephemeral_tls_material(Path(temporary_directory))
        environment = {
            **os.environ,
            "DEVCONTROL_ADMIN_TOKEN": ADMIN_TOKEN,
            "DEVCONTROL_HOST": "127.0.0.1",
            "DEVCONTROL_PORT": str(args.port),
            "DEVCONTROL_ADMIN_PORT": str(args.admin_port),
            "DEVCONTROL_DATABASE": str(GATEWAY_ROOT / "data" / "e2e.db"),
            "DEVCONTROL_TLS_CERT": str(gateway_cert),
            "DEVCONTROL_TLS_KEY": str(gateway_key),
            "NO_PROXY": "localhost,127.0.0.1",
            "no_proxy": "localhost,127.0.0.1",
        }
        creation_flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        gateway = subprocess.Popen(
            [sys.executable, "-m", "devcontrol_gateway"], cwd=GATEWAY_ROOT,
            env=environment, creationflags=creation_flags, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True,
        )
        try:
            wait_until_ready(gateway, base_url, ca_file)
            run_script("e2e_smoke.py", "--base-url", base_url, "--ca", str(ca_file),
                       "--pairing-code", get_pairing_code(admin_url))
            run_script("security_negative_test.py", "--base-url", base_url, "--ca", str(ca_file),
                       "--pairing-code", get_pairing_code(admin_url))
            run_script("performance_test.py", "--base-url", base_url, "--ca", str(ca_file),
                       "--count", str(args.performance_count), "--pairing-code", get_pairing_code(admin_url))
            if args.stability_seconds > 0:
                run_script("stability_test.py", "--base-url", base_url, "--ca", str(ca_file),
                           "--duration-seconds", str(args.stability_seconds), "--pid", str(gateway.pid),
                           "--pairing-code", get_pairing_code(admin_url))
        finally:
            if gateway.poll() is None:
                gateway.terminate()
            try:
                gateway.wait(timeout=5)
            except subprocess.TimeoutExpired:
                gateway.kill()
                gateway.wait(timeout=5)


if __name__ == "__main__":
    main()
