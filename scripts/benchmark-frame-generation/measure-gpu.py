#!/usr/bin/env python3
"""Run a command and sample its Apple GPU driver accounting by PID.

AppUsage.accumulatedGPUTime is a private IORegistry counter. The last observed
value is a lower bound if the process exits between samples; this is not a
per-kernel Metal timestamp. Keep stdout/stderr separate for benchmark JSON.
"""

import argparse
import json
import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path


def gpu_times_ns() -> dict[int, int]:
    raw = subprocess.check_output(
        ["ioreg", "-a", "-r", "-c", "AGXDeviceUserClient"],
        stderr=subprocess.DEVNULL,
    )
    totals: dict[int, int] = {}
    for entry in plistlib.loads(raw):
        creator = entry.get("IOUserClientCreator", "")
        match = re.match(r"pid (\d+),", creator)
        if match:
            pid = int(match.group(1))
            totals[pid] = totals.get(pid, 0) + sum(
                int(usage.get("accumulatedGPUTime", 0))
                for usage in entry.get("AppUsage", [])
            )
    return totals


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--stdout", required=True)
    parser.add_argument("--stderr", required=True)
    parser.add_argument("--stdin")
    parser.add_argument("--interval-ms", type=float, default=20)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("missing command after --")
    for path in (args.output, args.stdout, args.stderr):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
    baseline = gpu_times_ns()
    start = time.monotonic()
    samples = []
    maximum_by_pid: dict[int, int] = {}
    with open(args.stdout, "wb") as out, open(args.stderr, "wb") as err:
        source = open(args.stdin, "rb") if args.stdin else None
        child = subprocess.Popen(command, stdin=source, stdout=out, stderr=err)
        if source:
            source.close()
        while child.poll() is None:
            stamp = time.monotonic()
            try:
                snapshot = gpu_times_ns()
            except (OSError, subprocess.CalledProcessError, ValueError) as exc:
                print(f"GPU sample failed: {exc}", file=sys.stderr)
                snapshot = {}
            value = snapshot.get(child.pid)
            if value is not None:
                samples.append((stamp - start, value))
            for pid, total in snapshot.items():
                maximum_by_pid[pid] = max(maximum_by_pid.get(pid, 0), total)
            time.sleep(max(0, args.interval_ms / 1000 - (time.monotonic() - stamp)))
        return_code = child.wait()
    elapsed = time.monotonic() - start
    maximum = max((value for _, value in samples), default=None)
    deltas = sorted(
        ((pid, max(0, total - baseline.get(pid, 0))) for pid, total in maximum_by_pid.items()),
        key=lambda pair: pair[1], reverse=True,
    )
    result = {
        "command": command,
        "pid": child.pid,
        "exitCode": return_code,
        "wallSeconds": elapsed,
        "gpuCounter": "AGXDeviceUserClient.AppUsage.accumulatedGPUTime",
        "gpuCounterUnit": "ns",
        "gpuTimeObservedMS": maximum / 1_000_000 if maximum is not None else None,
        "gpuSamples": len(samples),
        "lastSampleAtSeconds": samples[-1][0] if samples else None,
        "gpuTimeIsLowerBound": True,
        "otherGPUTimeDeltasMS": [
            {"pid": pid, "gpuTimeMS": delta / 1_000_000}
            for pid, delta in deltas if pid != child.pid and delta > 0
        ][:12],
        "stdout": str(Path(args.stdout).resolve()),
        "stderr": str(Path(args.stderr).resolve()),
        "stdin": str(Path(args.stdin).resolve()) if args.stdin else None,
    }
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
