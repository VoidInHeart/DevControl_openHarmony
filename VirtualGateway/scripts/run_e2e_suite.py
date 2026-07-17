from __future__ import annotations

import os
import argparse
import subprocess
import sys
import time
from pathlib import Path

import httpx


GATEWAY_ROOT = Path(__file__).resolve().parents[1]
BASE_URL = "https://127.0.0.1:8443"
ADMIN_URL = "http://127.0.0.1:18444"
ADMIN_TOKEN = "devcontrol-local-admin"
CA_FILE = GATEWAY_ROOT / "certs" / "demo-ca.crt"


def wait_until_ready(process: subprocess.Popen[bytes]) -> None:
    for _ in range(40):
        if process.poll() is not None:
            raise RuntimeError(
                f"Gateway exited before readiness with code {process.returncode}"
            )
        try:
            response = httpx.get(
                BASE_URL + "/api/v1/health",
                verify=str(CA_FILE),
                timeout=1,
                trust_env=False,
            )
            response.raise_for_status()
            return
        except httpx.HTTPError:
            time.sleep(0.25)
    raise TimeoutError("Gateway did not become ready within 10 seconds")


def run_script(name: str, *arguments: str) -> None:
    subprocess.run(
        [sys.executable, str(GATEWAY_ROOT / "scripts" / name), *arguments],
        cwd=GATEWAY_ROOT,
        check=True,
        env={
            **os.environ,
            "NO_PROXY": "localhost,127.0.0.1",
            "no_proxy": "localhost,127.0.0.1",
        },
    )


def get_pairing_code() -> str:
    response = httpx.get(
        ADMIN_URL + "/admin/v1/pairing-code",
        headers={"X-Admin-Token": ADMIN_TOKEN},
        timeout=2,
        trust_env=False,
    )
    response.raise_for_status()
    pairing_code = response.json()["pairingCode"]
    if not isinstance(pairing_code, str):
        raise TypeError("Maintenance endpoint returned a non-string pairing code")
    return pairing_code


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--performance-count", type=int, default=1000)
    parser.add_argument("--stability-seconds", type=int, default=0)
    args = parser.parse_args()
    if not CA_FILE.is_file():
        raise SystemExit(
            "Demo certificate is missing. Run scripts/generate_demo_certs.py first."
        )
    environment = {
        **os.environ,
        "DEVCONTROL_ADMIN_TOKEN": ADMIN_TOKEN,
        "DEVCONTROL_HOST": "127.0.0.1",
        "DEVCONTROL_ADMIN_PORT": "18444",
        "DEVCONTROL_DATABASE": str(GATEWAY_ROOT / "data" / "e2e.db"),
        "NO_PROXY": "localhost,127.0.0.1",
        "no_proxy": "localhost,127.0.0.1",
    }
    creation_flags = (
        subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    )
    gateway = subprocess.Popen(
        [sys.executable, "-m", "devcontrol_gateway"],
        cwd=GATEWAY_ROOT,
        env=environment,
        creationflags=creation_flags,
    )
    try:
        wait_until_ready(gateway)
        run_script(
            "e2e_smoke.py", "--pairing-code", get_pairing_code()
        )
        run_script(
            "security_negative_test.py",
            "--pairing-code",
            get_pairing_code(),
        )
        run_script(
            "performance_test.py",
            "--count",
            str(args.performance_count),
            "--pairing-code",
            get_pairing_code(),
        )
        if args.stability_seconds > 0:
            run_script(
                "stability_test.py",
                "--duration-seconds",
                str(args.stability_seconds),
                "--pid",
                str(gateway.pid),
                "--pairing-code",
                get_pairing_code(),
            )
    finally:
        gateway.terminate()
        try:
            gateway.wait(timeout=5)
        except subprocess.TimeoutExpired:
            gateway.kill()
            gateway.wait(timeout=5)


if __name__ == "__main__":
    main()
