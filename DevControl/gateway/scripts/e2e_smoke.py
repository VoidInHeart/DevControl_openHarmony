from __future__ import annotations

import argparse
import json
from pathlib import Path

from e2e_common import (
    connect_websocket,
    make_command,
    pair,
    receive_command_cycle,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="https://localhost:8443")
    parser.add_argument("--ca", type=Path, default=Path("certs/demo-ca.crt"))
    parser.add_argument("--pairing-code", default="123456")
    args = parser.parse_args()

    credential, data_key, devices = pair(
        args.base_url, args.ca, args.pairing_code
    )
    light = next(device for device in devices if device["type"] == "light")
    socket = connect_websocket(args.base_url, args.ca, credential)
    try:
        heartbeat = json.loads(socket.recv())
        assert heartbeat["type"] == "heartbeat"
        envelope = make_command(
            data_key,
            light["id"],
            "setPower",
            light["stateVersion"],
            {"power": not light["power"]},
        )
        socket.send(json.dumps(envelope, separators=(",", ":")))
        result, state, result_latency, state_latency = receive_command_cycle(
            socket, str(envelope["messageId"]), str(light["id"])
        )
        assert result["success"] is True
        assert state is not None
        print(
            json.dumps(
                {
                    "result": "passed",
                    "commandLatencyMs": round(result_latency * 1000, 2),
                    "stateLatencyMs": round((state_latency or 0) * 1000, 2),
                    "stateVersion": state["stateVersion"],
                },
                ensure_ascii=False,
            )
        )
    finally:
        socket.close()


if __name__ == "__main__":
    main()
