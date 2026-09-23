# 1080p source → 720p VideoToolbox → 1080p MetalFX Spatial

Measured 2026-09-23 on Apple M1 / macOS 27.0. This tests the proposed 30 → 60 fps midpoint path, using the same bundled 1080p30 H.264 fixture as the in-app benchmark. The standalone [benchmark source](../../scripts/benchmark-frame-generation/benchmark-vt720-spatial.swift) and [three full-run results plus controls](vt720-spatial-m1-runs.json) are retained for M5 comparison.

For each adjacent pair, the first 1080p frame is already available at 720p from the preceding iteration. The timed path downsizes **one newly arrived 1080p frame** to 720p with `VTPixelTransferSession`, asks `VTFrameProcessor` for one 720p midpoint, imports that output as NV12 Metal textures, converts it to BGRA, runs XFrame's perceptual `MTLFXSpatialScaler` from 720p to 1080p, and composites it into a 1080p target. It waits for GPU completion. The original 1080p source frame can be shown at native resolution and is not upscaled. Video decoding, pixel-buffer allocation, session/scaler setup, display/drawable wait, stream jitter, and game input are outside the timed interval. Sixty adjacent pairs run sequentially; five warmups are excluded, leaving 55 measurements per run.

| Full run | Downsize p95 | VT p95 | Spatial completion p95 | Total p95 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 2.87 ms | 13.25 ms | 3.65 ms | **19.53 ms** |
| 2 | 2.90 ms | 13.34 ms | 3.63 ms | **19.80 ms** |
| 3 | 2.88 ms | 13.36 ms | 3.58 ms | **19.53 ms** |

Metal command timestamps for the spatial stage were about 1.8 ms p95; the spatial completion wall time includes NV12 texture wrapping, color conversion, MetalFX, final composition, submission, and GPU completion. The 30 fps source interval is **33.33 ms**, so the measured path has about **13.5 ms p95 processing headroom per source pair** on this M1 during the offline run. This is an offline compute result, not a demonstrated 60 Hz presentation rate in XFrame.

Stage interaction matters. With all frames downsized before timing and no spatial stage, VT's p95 was 6.69 ms, close to its standalone 720p result. Running immediate downsize but no spatial stage raised VT p95 to 9.12 ms. Running spatial on each pre-downsized midpoint raised VT p95 to 10.12 ms. The full chain raised VT p95 to about 13.3 ms. These controls show that adding stages changes observed VT completion time, so summing isolated component benchmarks would understate the end-to-end cost. They do not by themselves identify whether the extra time is resource contention, synchronization, cache state, or some combination.

Throughput and latency are different. One midpoint must be produced for each 33.33 ms source-frame pair; it does not need to finish in a separate 16.67 ms budget if output is buffered. The midpoint cannot be computed until the **next** source frame arrives. For steady 30 fps, a roughly 19.8 ms processing p95 implies the first original frame must be held at least `33.33 + 19.8 − 16.67 ≈ 36.5 ms` to show originals and generated midpoints at evenly spaced 60 Hz ticks. This is a lower bound on **additional presentation delay** relative to immediately showing an arrived source frame; network jitter, decode, display scheduling, and concurrent work add to it.

The generated frame takes a 1080p → 720p → 1080p path while original frames remain native 1080p. MetalFX cannot recover detail discarded before interpolation, and alternating sharpness or interpolation artifacts have not been evaluated. A visual quality test and a live XFrame presentation test are needed before offering this as a user-facing mode.

To rerun on another Mac from the repository root:

```sh
mkdir -p .build/benchmark-frame-generation
swiftc -O -parse-as-library scripts/benchmark-frame-generation/benchmark-vt720-spatial.swift \
  -o .build/benchmark-frame-generation/benchmark-vt720-spatial
.build/benchmark-frame-generation/benchmark-vt720-spatial \
  Sources/XFrame/Benchmark/BigBuckBunny-1080p30.mp4 Sources/XFrame/Shaders.metal full
```

The optional modes `pre-resize`, `no-spatial`, and `pre-resize-no-spatial` isolate stage interaction. Compare the reported fixture SHA-256, device, macOS version, and timing definitions across machines.
