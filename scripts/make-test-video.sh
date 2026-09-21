#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/fixtures
ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=60 \
  -t 12 -c:v libx264 -preset ultrafast -crf 23 -bf 3 -pix_fmt yuv420p \
  -color_range tv -colorspace bt709 -color_trc bt709 -color_primaries bt709 \
  -y .build/fixtures/h264-1080p60.mp4
