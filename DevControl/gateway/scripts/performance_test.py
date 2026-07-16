from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

from e2e_common import (
    connect_websocket,
    make_command,
    pair,
    receive_command_cycle,
)


def percentile(values: list[float], percent: float) -> float:
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(len(ordered) * percent))
    return ordered[index]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="https://localhost:8443")
    parser.add_argument("--ca", type=Path, default=Path("certs/demo-ca.crt"))
    parser.add_argument("--pairing-code", default="123456")
    parser.add_argument("--count", type=int, default=1000)
    parser.add_argument("--report", type=Path, default=Path("reports/performance.json"))
    args = parser.parse_args()

    credential, data_key, devices = pair(
        args.base_url, args.ca, args.pairing_code
    )
    light = next(device for device in devices if device["type"] == "light")
    version = int(light["stateVersion"])
    socket = connect_websocket(args.base_url, args.ca, credential)
    command_latencies: list[float] = []
    state_latencies: list[float] = []
    successes = 0
    failures: list[str] = []
    started = time.perf_counter()
    try:
        socket.recv()
        for index in range(args.count):
            envelope = make_command(
                data_key,
                str(light["id"]),
                "setBrightness",
                version,
                {"brightness": 40 + index % 61},
            )
            socket.send(json.dumps(envelope, separators=(",", ":")))
            result, state, command_latency, state_latency = receive_command_cycle(
                socket, str(envelope["messageId"]), str(light["id"])
            )
            command_latencies.append(command_latency * 1000)
            if state_latency is not None:
                state_latencies.append(state_latency * 1000)
            if result["success"] and state is not None:
                successes += 1
                version = int(state["stateVersion"])
            else:
                failures.append(json.dumps(result, ensure_ascii=False))
    finally:
        socket.close()

    duration = time.perf_counter() - started
    success_rate = successes / args.count * 100
    report = {
        "sampleCount": args.count,
        "successes": successes,
        "successRatePercent": round(success_rate, 3),
        "durationSeconds": round(duration, 3),
        "commandLatencyMs": {
            "average": round(statistics.fmean(command_latencies), 3),
            "p95": round(percentile(command_latencies, 0.95), 3),
            "maximum": round(max(command_latencies), 3),
        },
        "stateLatencyMs": {
            "average": round(statistics.fmean(state_latencies), 3),
            "p95": round(percentile(state_latencies, 0.95), 3),
            "maximum": round(max(state_latencies), 3),
        },
        "failures": failures[:10],
        "passed": (
            success_rate >= 99.5
            and percentile(command_latencies, 0.95) <= 500
            and percentile(state_latencies, 0.95) <= 1000
        ),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
