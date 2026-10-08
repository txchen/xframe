# Nonblocking HUD refresh and compact metric layout

Status: ready-for-human

## Request

User approved optimizing HUD refresh so observing performance does not make playback stutter, and supplied an Apple Metal HUD screenshot as the visual reference.

## Scope and implementation

- First isolation increment: no periodic statistics, formatting or HUD update inside `MetalRenderer.draw(in:)`. Preserve cheap EOF/failure state reads independently of diagnostics.
- `HUDSampler` performs background collection/formatting, awaits delivery, then sleeps 500 ms. No catch-up refresh queue; cancelled generations cannot deliver. Hidden stops display sampling, not media instrumentation.
- Timing windows are explicitly copied under a bounded lock; sorting and summary calculation run after unlocking. Live/local snapshot and live diagnostic export no longer hold the media lock during performance summaries. Snapshots across media and timing locks are intentionally not atomic across the entire pipeline.
- Right-aligned, fixed-layout dark panel with monospaced label/value columns, muted labels, teal accents and section headings. Rounded border, no blur. Compact/Detailed/Hidden and click-through retained. Live graph is a 30-second history of measured rolling 2-second OUT FPS, not instantaneous frame time. Missing samples and gaps are not filled. Local graph uses session averages and is labelled accordingly.
- Preserve full legacy diagnostic text as accessibility content; visible Detailed focuses on core pipeline and stream health. Controller footer omits packet sequence. Requested quality remains labelled requested. No claim of remote game FPS or full input-to-photon latency.
- Small playback windows constrain the panel height and scale its painting without per-row Auto Layout.

## Limits

This is not the independent-render-thread increment. Renderer remains MainActor; unrelated UI stalls can still interfere. Scaling changes still report effective mode to UI on the main actor. Compact currently collects full timing summaries (off the media locks), not a reduced subset. Basic telemetry locks, CPU/GPU resources and compositing still have bounded but nonzero overhead. No zero-overhead or measured live pacing improvement claim.

The prior CAMetalDisplayLink regression must be addressed by a separate measured prototype, not silently folded into this UI change. See ../nonblocking-hud-research.md.

## Comments

Implemented the first isolation and UI increment. Five new tests cover formatting/units, bounded history, blocked background collection and cancelled delivery, concurrent timing writes/snapshots, and rendered Compact/Detailed previews. Live side-by-side acceptance and full-window/small-window interaction remain manual follow-up; status reflects that validation gate, not missing implementation.
