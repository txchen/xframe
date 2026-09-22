# Spatial scaling implementation and validation

Date: 2026-09-22. Apple M1 Mac mini, macOS 27 SDK, 3840×2160 fullscreen backing surface.

## Delivered behavior

View → Video Scaling exposes Original, Integer Scaling, and MetalFX Spatial. Changes apply during playback and persist across restarts. Cloud video, local video and the static test pattern use the same policy. Original remains the first-launch default.

MetalFX follows the fitted picture area; non-enlarging output, unsupported devices and initialization failure use Original with a HUD reason. Integer Scaling is active only for exact fullscreen integer enlargement; windowed/noninteger output uses Original and returning to eligible fullscreen restores pixel replication.

## Rendering and timing contracts

- Original retains the direct NV12-to-drawable bilinear path. Integer NV12 sampling snaps to a luma pixel center before reconstructing chroma, so all four pixels in a 2×2 block have identical color.
- MetalFX receives source-resolution BGRA8 SDR color, with the existing BT.601/709 limited-range conversion. `.perceptual` mode operates on encoded color values; no sRGB texture conversion is inserted. The final scaler output uses private storage and its declared texture-usage requirements.
- All work uses one command buffer and one serial command queue per frame. Tracked input/output surfaces are reused in queue order. The command completion retains the scaler generation and source surfaces. Three in-flight submissions bound retired size generations; no synchronous GPU wait or CPU pixel readback occurs in production.
- Three exclusively leased timestamp buffers per scaler generation prevent CPU readback from racing a later submission. The final drawable pass clears old counter attachments when bypassing. Failed initialization is cached for the current configuration rather than retried every frame.
- `MetalFX GPU span` measures source-conversion fragment completion → final-composition fragment start, including the scaler and intervening scheduling. Vertex-stage timestamps cannot define this interval because vertex execution may overlap earlier fragment work; that attempted boundary produced invalid ordering and was replaced. It is neither isolated kernel time nor end-to-end latency.
- Whole-command GPU timing and same-frame drawable `presentedTime` remain separate. Scaler distributions reset on configuration changes and reject retired callbacks. Other timing windows contain the most recent 256 samples; warm up after switching modes before comparing them. Schema 8 includes mode, dimensions, bypass reason and scaler distribution without free-form sensitive error text.

## Automated and device checks

- Final full Swift suite: **128 tests passed**. Log: `.build/scaling-tests.log`. Signed build: `.build/scaling-build.log`; focused Metal validation: `.build/scaling-metal-validation.log`.
- Real M1 GPU readback verifies BT.601/709 black, white and nonneutral chroma for both Original and Integer Scaling, and checks every 2×2 output block for equality.
- Real MetalFX 1920×1080→3840×2160 execution preserves black/white, gray and colored patch interiors within two output code values. This is a color check, not evidence of improved natural-image detail.
- Isolated 60-sample offscreen run after five warmups: total GPU mean 3.65 ms / p95 3.70 ms; scaler span mean 3.19 ms / p95 3.20 ms. Offscreen timing varies with GPU clock/load and is not sustained gameplay evidence.
- Focused GPU tests passed with `MTL_DEBUG_LAYER=1` and no Metal validation errors. Its timings were intentionally excluded from the performance comparison because another playback workload was active.
- Signed release app built and passed `codesign --verify --deep --strict`.

## Native UI checks

- Test pattern: Original, Integer Scaling and MetalFX render at 3840×2160; circle geometry, orientation, color patches and four corner markers remain visible. Screenshots are scaled UI observations, not pixel-perfect quality comparisons.
- Integer mode in a 3064×1634 window reports Original with the fullscreen reason; fullscreen re-entry reports Integer Scaling at 3840×2160. The Integer selection survived an app restart and applied to the next source.
- A repeated 120-second 1080p60 H.264 fixture played with hardware decode and zero decode errors; MetalFX → Integer mode changed during playback. Exit/re-enter fullscreen restored Integer mode without reopening the source. Transition/startup skips are not treated as steady-state failures or as a clean throughput benchmark.
- Opening a local file while the previous test-pattern window was fullscreen briefly produced the existing fullscreen-exit failure message; explicit fullscreen re-entry succeeded. Normal playback exit/re-entry also succeeded. This observation is not a claim that every native fullscreen transition is flawless.

## Live comparison

Same Palworld main-menu session, HQ requested / received 1920×1080 H.264, Balanced pacing, 3840×2160 fullscreen, Detailed HUD, input disabled during timing comparisons. Modes were changed through the native menu without reconnecting. The table records HUD rolling-window snapshots after warmup, not confidence intervals or full input-to-photon latency.

| Mode | Recent IN / OUT fps | Whole GPU mean / p95 ms | Scaler span mean / p95 ms | Local presentation mean / p95 ms |
| --- | --- | --- | --- | --- |
| Integer | 60.0 / 60.0 | 0.6 / 0.7 | n/a | 37.9 / 40.5 |
| Original | 60.0 / 60.0 | 0.6 / 0.7 | n/a | 31.0 / 34.5 |
| MetalFX | 60.0 / 60.0 | 6.6 / 6.7 | 5.68 / 5.71 | 57.9 / 61.7 |

Integer observation endpoints: decoded 2344→3973, presented 2284→3906, skipped 57→65. Original endpoints: decoded 4456→5662, presented 4389→5587, skipped 65→73. Endpoint queue occupancy differs, so these differences are not a precise one-to-one frame-loss calculation. The Original/Integer comparison snapshots reported zero decode errors, zero packet loss/NACKs, bounded 2-frame queues and attached/unmuted audio. MetalFX steady observation endpoints were decoded 6869→8318, presented 6793→8233 and skipped 73→81, with zero decode errors. Its earlier snapshot measured local presentation 47.6 ms mean / 50.1 ms p95; arrival/queue variability means the later 57.9 ms is not a controlled estimate of added scaler latency. Whole-frame GPU cost clearly increased, and final display wait also increased in these samples. These short menu observations do not establish fast-gameplay or long-session acceptance.

## Switching, input, resources and cleanup

- Nine consecutive live mode changes (Original → Integer → MetalFX, repeated three times) completed in the same session. All nine HUD observations showed the requested effective mode, zero decode errors and unchanged skip count (91). No reconnect was performed.
- MetalFX adapted from fullscreen 3840×2160 to a 2905×1634 fitted picture in the 3064×1634 window. Both resize and fullscreen transitions have transient presentation misses; these are excluded from steady-state claims.
- With MetalFX active, enabling the existing keyboard gamepad and pressing G moved the Palworld menu selection down; T restored it. This verifies host-visible keyboard-to-game input, not physical-controller latency. Audio remained attached/unmuted and the exported report contains received audio packets and nonzero energy; acoustic playback/A-V perception was not independently judged.
- Process samples every five seconds: 48 samples, RSS 193424–215344 KiB including startup. Immediately before nine mode changes RSS was 214464 KiB; after switching and window transition it was 215040 KiB. No large accumulating increase was observed in this short check; it is not a leak-proof or thermal-soak claim. CPU samples and timestamps are in `.build/scaling-validation/process.jsonl`; GPU utilization and thermal state were not measured.
- Original scaling and disabled keyboard input were restored. End Session completed with the UI reporting “Session ended.” The real schema-8 export was saved and parsed at `.build/scaling-validation/stream-final.json`: stopped, duration 249.25 s, one decoder configuration, 14135 decoded frames, zero decode errors/recovery skips, peak queue two, zero lost packets and two NACKs. Final presented/skipped totals include startup, UI transitions, background library/export work and test-suite contention; they are not the steady-state comparison.

## Remaining acceptance

Natural-content text, foliage, fast pans, compression artifacts and subjective preference require comparison across representative games; test-pattern sharpness alone does not establish superiority. Physical controller/audio perception, long thermal soak, and other display/GPU coverage must be distinguished from rendering tests. Additional sharpening and FSR remain separate increments; the combined roadmap item stays open.
