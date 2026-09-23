#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/.build/fixtures"
SOURCE="$FIXTURES/bbb-source-1080p60.mp4"
OUTPUT="$FIXTURES/fg-bbb-1080p30.mp4"
SOURCE_URL="https://raw.githubusercontent.com/bower-media-samples/big-buck-bunny-1080p-60fps-30s/c4c7ec6aa5d68944d32faa28f332f999c8866cbc/video.mp4"
SOURCE_SHA="badb5340b91a89f7b9910dc42f507bb2afdf857e054012c100d56ea3bde775a6"

for tool in curl shasum ffmpeg ffprobe python3; do
  command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 69; }
done
mkdir -p "$FIXTURES"
if [[ ! -s "$SOURCE" ]]; then
  curl -fL --retry 3 "$SOURCE_URL" -o "$SOURCE.partial"
  mv "$SOURCE.partial" "$SOURCE"
fi
ACTUAL_SHA="$(shasum -a 256 "$SOURCE" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$SOURCE_SHA" ]] || {
  echo "Source SHA-256 mismatch: $ACTUAL_SHA" >&2; exit 65;
}
if [[ ! -s "$OUTPUT" ]]; then
  ffmpeg -hide_banner -loglevel error -y -ss 6 -t 6 -i "$SOURCE" \
    -an -vf fps=30 -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p "$OUTPUT.partial.mp4"
  mv "$OUTPUT.partial.mp4" "$OUTPUT"
fi
FRAME_COUNT="$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of default=nw=1:nk=1 "$OUTPUT")"
[[ "$FRAME_COUNT" == 180 ]] || { echo "Expected 180 frames, got $FRAME_COUNT" >&2; exit 65; }
printf '%s\n' "$OUTPUT"
