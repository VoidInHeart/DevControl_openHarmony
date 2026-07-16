from __future__ import annotations

import argparse
import copy
import json
import secrets
from pathlib import Path

import httpx

from e2e_common import (
    connect_websocket,
    make_command,
    pair,
    receive_command_cycle,
)


def send_and_expect_error(
    socket,
    envelope: dict[str, object],
    expected_code: str,
) -> None:
    socket.send(json.dumps(envelope, separators=(",", ":")))
    result, state, _, _ = receive_command_cycle(
        socket,
        str(envelope["messageId"]),
        str(envelope["deviceId"]),
    )
    assert state is None
    assert result["success"] is False
    error = result["error"]
    assert isinstance(error, dict)
    assert error["code"] == expected_code


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="https://localhost:8443")
    parser.add_argument("--ca", type=Path, default=Path("certs/demo-ca.crt"))
    parser.add_argument("--pairing-code", default="123456")
    args = parser.parse_args()

    try:
        httpx.get(args.base_url + "/api/v1/health", timeout=5)
    except httpx.TransportError:
        pass
    else:
        raise AssertionError("Untrusted demo certificate was accepted by system trust")

    credential, data_key, devices = pair(
        args.base_url, args.ca, args.pairing_code
    )
    light = next(device for device in devices if device["type"] == "light")
    socket = connect_websocket(args.base_url, args.ca, credential)
    try:
        socket.recv()

        tampered_ciphertext = make_command(
            data_key,
            str(light["id"]),
            "setPower",
            int(light["stateVersion"]),
            {"power": not light["power"]},
        )
        ciphertext = str(tampered_ciphertext["ciphertext"])
        tampered_ciphertext["ciphertext"] = (
            ("A" if ciphertext[0] != "A" else "B") + ciphertext[1:]
        )
        send_and_expect_error(socket, tampered_ciphertext, "REPLAY_DETECTED")

        tampered_aad = make_command(
            data_key,
            str(light["id"]),
            "setPower",
            int(light["stateVersion"]),
            {"power": not light["power"]},
        )
        tampered_aad["action"] = "setBrightness"
        send_and_expect_error(socket, tampered_aad, "REPLAY_DETECTED")

        expired = make_command(
            data_key,
            str(light["id"]),
            "setPower",
            int(light["stateVersion"]),
            {"power": not light["power"]},
        )
        expired["timestamp"] = int(expired["timestamp"]) - 31_000
        send_and_expect_error(socket, expired, "REPLAY_DETECTED")

        first = make_command(
            data_key,
            str(light["id"]),
            "setBrightness",
            int(light["stateVersion"]),
            {"brightness": 63},
        )
        socket.send(json.dumps(first, separators=(",", ":")))
        result, state, _, _ = receive_command_cycle(
            socket,
            str(first["messageId"]),
            str(light["id"]),
        )
        assert result["success"] is True and state is not None

        repeated_nonce = make_command(
            data_key,
            str(light["id"]),
            "setBrightness",
            int(state["stateVersion"]),
            {"brightness": 64},
        )
        repeated_nonce["nonce"] = first["nonce"]
        send_and_expect_error(socket, repeated_nonce, "REPLAY_DETECTED")

        duplicate = copy.deepcopy(first)
        socket.send(json.dumps(duplicate, separators=(",", ":")))
        duplicate_result, duplicate_state, _, _ = receive_command_cycle(
            socket,
            str(duplicate["messageId"]),
            str(light["id"]),
            require_state=False,
        )
        assert duplicate_result["success"] is True
        assert duplicate_state is None

        invalid_credential = secrets.token_urlsafe(32)
        try:
            invalid_socket = connect_websocket(
                args.base_url, args.ca, invalid_credential
            )
        except Exception:
            pass
        else:
            try:
                message = invalid_socket.recv()
                if message:
                    raise AssertionError("Invalid credential opened a WSS session")
            finally:
                invalid_socket.close()
    finally:
        socket.close()

    print(
        json.dumps(
            {
                "result": "passed",
                "checks": [
                    "untrusted-certificate-rejected",
                    "ciphertext-tamper-rejected",
                    "aad-tamper-rejected",
                    "expired-timestamp-rejected",
                    "reused-nonce-rejected",
                    "duplicate-message-id-idempotent",
                    "invalid-credential-rejected",
                ],
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
