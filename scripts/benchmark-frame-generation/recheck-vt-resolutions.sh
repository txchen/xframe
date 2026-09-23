#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
source_video="$root/Sources/XFrame/Benchmark/BigBuckBunny-1080p30.mp4"
output_dir="${1:-$root/.build/benchmark-frame-generation/resolution-recheck/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$output_dir"

swiftc -O -parse-as-library \
  "$root/scripts/benchmark-frame-generation/benchmark-vt.swift" \
  -o "$output_dir/benchmark-vt"
ffmpeg -hide_banner -loglevel error -y -i "$source_video" \
  -vf scale=1280:720:flags=lanczos -frames:v 61 -an \
  -c:v libx264 -preset fast -crf 18 "$output_dir/720.mp4"

run_case() {
  local size="$1" trial="$2" input="$source_video"
  if [[ "$size" == 720 ]]; then input="$output_dir/720.mp4"; fi
  /usr/bin/time -lp "$output_dir/benchmark-vt" "$input" 60 \
    > "$output_dir/${size}-${trial}.json" \
    2> "$output_dir/${size}-${trial}.time"
}

# The alternating order catches a run-order or short-term thermal explanation.
run_case 720 1
run_case 1080 1
run_case 1080 2
run_case 720 2
run_case 720 3
run_case 1080 3

python3 - "$source_video" "$output_dir" <<'PY'
import hashlib
import json
import pathlib
import platform
import re
import sys

source = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def seconds(label, text):
    match = re.search(rf"^{label}\s+([\d.]+)$", text, re.MULTILINE)
    if not match:
        raise ValueError(f"Missing {label} in time output")
    return float(match.group(1))

runs = []
for size, trial in [(720, 1), (1080, 1), (1080, 2), (720, 2), (720, 3), (1080, 3)]:
    result = json.loads((out / f"{size}-{trial}.json").read_text())
    timing = (out / f"{size}-{trial}.time").read_text()
    assert result["pairs"] == 60 and result["width"] == size * 16 // 9
    runs.append({
        "size": size, "trial": trial,
        "medianMS": result["steadyP50MS"],
        "p95MS": result["steadyP95MS"],
        "decodeMedianMS": result["decodeP50MS"],
        "sessionStartMS": result["sessionStartMS"],
        "realSeconds": seconds("real", timing),
        "userCPUSeconds": seconds("user", timing),
    })

summary = {
    "machine": platform.machine(), "macOS": platform.mac_ver()[0],
    "device": result["device"], "pairsPerRun": 60,
    "warmupPairsPerRun": 5,
    "sourceSHA256": digest(source),
    "transcoded720SHA256": digest(out / "720.mp4"),
    "method": "Native-size 720p/1080p decoded video; processor wall time; 720p transcode and decode outside measured processor time.",
    "runs": runs,
}
(out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
for row in runs:
    print(f"{row['size']:4}p #{row['trial']}: "
          f"median {row['medianMS']:.2f} ms, p95 {row['p95MS']:.2f} ms, "
          f"user CPU {row['userCPUSeconds']:.2f} s")
print(f"Saved {out / 'summary.json'}")
PY
