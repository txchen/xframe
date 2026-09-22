#!/bin/bash
# Isolated, pinned upstream CLI. Models and outputs stay under ignored .build/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
experiment="$root/.build/experiments/mlx-dlss"
upstream="$experiment/upstream"
revision=0ca2deab092fe6f3e331bf4f616271dbc64521d0
action="${1:-status}"
if [[ $# -gt 0 ]]; then shift; fi
mkdir -p "$experiment"

case "$action" in
  prepare)
    if ! xcrun --find metal >/dev/null 2>&1; then
      echo "Metal shader compiler unavailable. Select an Xcode/Metal toolchain providing xcrun metal, then retry." >&2
      exit 69
    fi
    if [[ ! -d "$upstream" ]]; then
      git clone https://github.com/iamwavecut/MLX-DLSS.git "$upstream"
      git -C "$upstream" checkout --detach "$revision"
    fi
    if [[ "$(git -C "$upstream" rev-parse HEAD)" != "$revision" ]] ||
       [[ -n "$(git -C "$upstream" status --porcelain)" ]]; then
      echo "Upstream must be clean at $revision; preserve/review local changes first." >&2
      exit 1
    fi
    if [[ ! -x "$experiment/tools-env/bin/python" ]]; then
      python3 -m venv "$experiment/tools-env"
    fi
    "$experiment/tools-env/bin/python" -m pip install cmake==4.4.3 ninja==1.13.2
    export PATH="$experiment/tools-env/bin:$PATH"
    swift build --package-path "$upstream" --build-system native -c release \
      --product mlxdlss --jobs 2 2>&1 | tee "$experiment/swift-build.log"
    bin_path="$(swift build --package-path "$upstream" --build-system native -c release --show-bin-path)"
    MLXDLSS_PREPARE_SKIP_SWIFT_BUILD=1 "$upstream/scripts/prepare-mlx-metallib.sh" \
      "$bin_path" 2>&1 | tee "$experiment/metal-build.log"
    printf '%s\n' "$bin_path/mlxdlss" > "$experiment/cli-path.txt"
    ;;
  run)
    if [[ ! -f "$experiment/cli-path.txt" ]]; then
      echo "Run $0 prepare first." >&2
      exit 1
    fi
    cli="$(cat "$experiment/cli-path.txt")"
    exec "$cli" "$@"
    ;;
  status)
    sw_vers
    swift --version
    xcrun --find metal || true
    if [[ -d "$upstream/.git" ]]; then git -C "$upstream" rev-parse HEAD; fi
    if [[ -f "$experiment/cli-path.txt" ]]; then cat "$experiment/cli-path.txt"; fi
    ;;
  *)
    echo "Usage: $0 {prepare|status|run <upstream CLI arguments>}" >&2
    exit 2
    ;;
esac
