from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import httpx
import psutil
import websocket

from e2e_common import connect_websocket, pair


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="https://localhost:8443")
    parser.add_argument("--ca", type=Path, default=Path("certs/demo-ca.crt"))
    parser.add_argument("--pairing-code", default="123456")
    parser.add_argument("--duration-seconds", type=int, default=1800)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--max-growth-mb", type=float, default=32)
    parser.add_argument(
        "--report", type=Path, default=Path("reports/stability.json")
    )
    args = parser.parse_args()

    credential, _, _ = pair(args.base_url, args.ca, args.pairing_code)
    headers = {"Authorization": "Bearer " + credential}
    process = psutil.Process(args.pid)
    socket = connect_websocket(args.base_url, args.ca, credential)
    socket.settimeout(5)
    started = time.monotonic()
    initial_rss = process.memory_info().rss
    maximum_rss = initial_rss
    heartbeat_count = 0
    state_event_count = 0
    snapshot_count = 0
    next_snapshot_at = started
    try:
        while time.monotonic() - started < args.duration_seconds:
            maximum_rss = max(maximum_rss, process.memory_info().rss)
            now = time.monotonic()
            if now >= next_snapshot_at:
                with httpx.Client(
                    verify=str(args.ca), timeout=5, trust_env=False
                ) as client:
                    snapshot = client.get(
                        args.base_url + "/api/v1/devices", headers=headers
                    )
                    snapshot.raise_for_status()
                    assert len(snapshot.json()["devices"]) == 4
                snapshot_count += 1
                next_snapshot_at = now + 10
            try:
                message = json.loads(socket.recv())
            except websocket.WebSocketTimeoutException:
                continue
            if message.get("type") == "heartbeat":
                heartbeat_count += 1
            elif message.get("type") == "state.changed":
                state_event_count += 1
    finally:
        socket.close()

    final_rss = process.memory_info().rss
    growth_mb = (final_rss - initial_rss) / 1024 / 1024
    maximum_growth_mb = (maximum_rss - initial_rss) / 1024 / 1024
    report = {
        "durationSeconds": args.duration_seconds,
        "heartbeats": heartbeat_count,
        "stateEvents": state_event_count,
        "snapshots": snapshot_count,
        "initialRssMb": round(initial_rss / 1024 / 1024, 3),
        "finalRssMb": round(final_rss / 1024 / 1024, 3),
        "growthMb": round(growth_mb, 3),
        "maximumGrowthMb": round(maximum_growth_mb, 3),
        "passed": (
            heartbeat_count > 0
            and state_event_count > 0
            and snapshot_count > 0
            and maximum_growth_mb <= args.max_growth_mb
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
