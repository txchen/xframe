#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="$ROOT/scripts/benchmark-frame-generation"
BASE="$ROOT/.build/benchmark-frame-generation"
WORK="$BASE/runs/$(date -u +%Y%m%dT%H%M%SZ)-$$"
DLSS_SOURCE="${DLSS_SOURCE:-$BASE/MLX-DLSS}"
INPUT="${FG_INPUT:-}"
PAIRS="${FG_PAIRS:-60}"
PIN="0ca2deab092fe6f3e331bf4f616271dbc64521d0"

[[ "$PAIRS" =~ ^[1-9][0-9]*$ ]] || { echo "FG_PAIRS must be positive" >&2; exit 64; }
for tool in swift git python3 unzip ioreg ffmpeg ffprobe; do
  command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 69; }
done
mkdir -p "$WORK"
if [[ -z "$INPUT" ]]; then INPUT="$($TOOLS/prepare-video.sh)"; fi
[[ -f "$INPUT" ]] || { echo "Missing input: $INPUT" >&2; exit 66; }
if [[ -z "${FG_WEIGHTS:-}" || ! -s "$FG_WEIGHTS" ]]; then
  echo "Set FG_WEIGHTS to locally extracted framegen.safetensors" >&2; exit 66
fi

swiftc -parse-as-library "$TOOLS/benchmark-vt.swift" -o "$WORK/benchmark-vt"
python3 "$TOOLS/measure-gpu.py" \
  --output "$WORK/vt-gpu.json" --stdout "$WORK/vt.json" --stderr "$WORK/vt.stderr" -- \
  "$WORK/benchmark-vt" "$INPUT" "$PAIRS" "$WORK/vt-preview.png"

if [[ ! -d "$DLSS_SOURCE/.git" ]]; then
  git clone https://github.com/iamwavecut/MLX-DLSS.git "$DLSS_SOURCE"
fi
git -C "$DLSS_SOURCE" fetch origin "$PIN"
git -C "$DLSS_SOURCE" checkout --detach "$PIN"
swift build --package-path "$DLSS_SOURCE" --build-system native -c release --product mlxdlss
DLSS_BIN="$DLSS_SOURCE/.build/release/mlxdlss"
if [[ -n "${MLX_METALLIB:-}" ]]; then
  cp "$MLX_METALLIB" "$DLSS_SOURCE/.build/release/mlx.metallib"
elif xcrun --find metal >/dev/null 2>&1 && command -v cmake >/dev/null && command -v ninja >/dev/null; then
  MLXDLSS_PREPARE_SKIP_SWIFT_BUILD=1 "$DLSS_SOURCE/scripts/prepare-mlx-metallib.sh" \
    "$DLSS_SOURCE/.build/release"
else
  # The pinned mlx-swift 0.31.6 contains MLX core 0.31.1. Its matching
  # published wheel includes the precompiled Metal kernels, so CLT-only Macs
  # can run this benchmark without installing full Xcode.
  WHEELS="$WORK/wheels"
  mkdir -p "$WHEELS"
  python3 -m pip download --no-deps --only-binary=:all: mlx-metal==0.31.1 -d "$WHEELS"
  WHEEL="$(find "$WHEELS" -maxdepth 1 -name 'mlx_metal-0.31.1-*.whl' -print -quit)"
  [[ -n "$WHEEL" ]] || { echo "Matching MLX Metal wheel unavailable" >&2; exit 69; }
  unzip -p "$WHEEL" mlx/lib/mlx.metallib > "$DLSS_SOURCE/.build/release/mlx.metallib"
fi
[[ -s "$DLSS_SOURCE/.build/release/mlx.metallib" ]] || { echo "Missing MLX metallib" >&2; exit 69; }

python3 "$TOOLS/measure-gpu.py" \
  --output "$WORK/dlss-gpu.json" --stdout "$WORK/dlss.json" --stderr "$WORK/dlss.stderr" -- \
  "$DLSS_BIN" process-video "$INPUT" --output "$WORK/dlss-output.mp4" \
  --framegen-weights "$FG_WEIGHTS" --factor 2 --frames "$((PAIRS + 1))" --audio off

DIMENSIONS="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INPUT")"
WIDTH="${DIMENSIONS%x*}"
HEIGHT="${DIMENSIONS#*x}"
ffmpeg -hide_banner -loglevel error -y -i "$INPUT" -frames:v "$((PAIRS + 1))" \
  -f rawvideo -pix_fmt rgb24 "$WORK/input.rgb"
python3 "$TOOLS/measure-gpu.py" \
  --output "$WORK/dlss-stream-gpu.json" --stdout /dev/null --stderr "$WORK/dlss-stream.stderr" \
  --stdin "$WORK/input.rgb" -- \
  "$DLSS_BIN" framegen-stream --weights "$FG_WEIGHTS" --width "$WIDTH" --height "$HEIGHT" \
  --factor 2 --batch 1 --format u8
python3 "$TOOLS/summarize.py" "$WORK" "$INPUT" "$PAIRS"
