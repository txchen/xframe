#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
rounds="${1:-3}"
if [[ ! "$rounds" =~ ^[1-9][0-9]?$ ]] || (( rounds > 20 )); then
    echo "Usage: bash scripts/check-headless.sh [rounds: 1-20]" >&2
    exit 2
fi
for fixture in .build/fixtures/h264-1080p60.mp4 .build/fixtures/h264-1080p60.h264; do
    if [[ ! -s "$fixture" ]]; then
        echo "Missing fixture: $fixture. Run bash scripts/make-test-video.sh first." >&2
        exit 1
    fi
done
mkdir -p .build/headless-checks
run_dir="$(mktemp -d .build/headless-checks/run.XXXXXX)"
echo "Logs: $run_dir"
for ((round=1; round<=rounds; round++)); do
    echo "Test round $round/$rounds"
    if ! bash scripts/test.sh >"$run_dir/tests-$round.log" 2>&1; then
        tail -80 "$run_dir/tests-$round.log"
        echo "Failed round $round; logs retained in $run_dir" >&2
        exit 1
    fi
    tail -1 "$run_dir/tests-$round.log"
done
echo "Release build"
if ! bash scripts/build-app.sh >"$run_dir/build.log" 2>&1; then
    tail -80 "$run_dir/build.log"
    exit 1
fi
echo "Passed $rounds test rounds and release build. No app launch or UI interaction."
