# XFrame 0.1.4 — Original presentation queue

- Bound Original live playback to two frames awaiting actual presentation. GPU completion no longer allows that display queue to grow without this separate limit.
- Handle abandoned draws, GPU errors, duplicate completion and scaling-mode transitions without leaking presentation reservations.
- Expand exported frame diagnostics with submission/GPU timestamps and discard reasons (schema 10); add a local analysis script.
- Document remaining latency questions and M5 validation steps in [the research document](https://github.com/txchen/xframe/blob/v0.1.4/docs/presentation-latency-research.md).

On M1/4K60, controlled extra-draw stress kept median display wait near 22–23 ms instead of the 39–47 ms states seen in two baseline blocks. Ordinary streaming was essentially unchanged and remained near 60 fps. This is a queue-buildup fix, **not a claim that every frame is now one refresh faster**. Normal ~23 ms display wait remains under investigation. MetalFX scheduling is unchanged; M5 still needs user validation.

Validation: 213 tests passed before packaging; two real streaming sessions verified startup, fullscreen transitions, MetalFX-to-Original and reconnect. See the research document for measurement boundaries and limitations.

Requires Apple Silicon and macOS 27 or later.

```sh
brew update
brew upgrade --cask txchen/tap/xframe
```
