#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

pin="0ca2deab092fe6f3e331bf4f616271dbc64521d0"
source_dir="${XFRAME_MLX_SOURCE:-$PWD/.build/benchmark-mlx-dlss/source}"
output_dir="${1:?Expected app Contents/MacOS path}"
if [[ ! -d "$source_dir/.git" ]]; then
    mkdir -p "$(dirname "$source_dir")"
    git clone https://github.com/iamwavecut/MLX-DLSS.git "$source_dir"
fi
if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$pin" ]]; then
    git -C "$source_dir" fetch origin "$pin"
    git -C "$source_dir" checkout --detach "$pin"
fi
swift build --package-path "$source_dir" --build-system native -c release --product mlxdlss
cp "$source_dir/.build/release/mlxdlss" "$output_dir/mlxdlss-benchmark"

if [[ -n "${XFRAME_MLX_METALLIB:-}" ]]; then
    cp "$XFRAME_MLX_METALLIB" "$output_dir/mlx.metallib"
elif [[ -s "$source_dir/.build/release/mlx.metallib" ]]; then
    cp "$source_dir/.build/release/mlx.metallib" "$output_dir/mlx.metallib"
else
    # MLX Swift 0.31.6 uses MLX core 0.31.1. This official wheel supplies
    # matching precompiled kernels on Command Line Tools-only build machines.
    wheel_dir="$PWD/.build/benchmark-mlx-dlss/wheels"
    mkdir -p "$wheel_dir"
    python3 -m pip download --no-deps --only-binary=:all: mlx-metal==0.31.1 -d "$wheel_dir"
    wheel="$(find "$wheel_dir" -maxdepth 1 -name 'mlx_metal-0.31.1-*.whl' -print -quit)"
    [[ -n "$wheel" ]] || { echo "Matching MLX Metal wheel unavailable" >&2; exit 69; }
    echo 'e7324b7c56b519ae67c025d3ced07e5d35bc3a9f19d4c45fe4927f385148c59e  '"$wheel" | shasum -a 256 -c -
    unzip -p "$wheel" mlx/lib/mlx.metallib > "$output_dir/mlx.metallib"
fi
[[ -s "$output_dir/mlx.metallib" ]] || { echo "Missing MLX metallib" >&2; exit 69; }

license_dir="$(dirname "$output_dir")/Resources/Licenses"
mkdir -p "$license_dir"
cp -f "$source_dir/LICENSE" "$license_dir/MLX-DLSS-LICENSE.txt"
cp -f "$source_dir/NOTICE" "$license_dir/MLX-DLSS-NOTICE.txt"
cp -f "$source_dir/.build/checkouts/mlx-swift/LICENSE" "$license_dir/MLX-LICENSE.txt"
