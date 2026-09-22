# Motion ghosting visible with MetalFX

Status: wontfix
Type: quality-observation

## User observation (2026-09-22)

MetalFX looks substantially better than Original overall, but slight ghosting is visible during movement. On a same-scene comparison, the user reports that ghosting is visible only with MetalFX. Integer Scaling avoids blur and makes text particularly sharp.

This establishes a mode-specific visual symptom, not its cause. Do not dismiss it as source-stream ghosting or claim a fix based on static images or build tests.

User clarification: considers the slight artifact an acceptable spatial-upscaling quality tradeoff, similar to FSR 1, rather than an implementation bug. Retain this observation without a bug-fix or acceptance-blocking requirement. This disposition does not establish that temporal ghosting is inherent to spatial scaling.

## Optional future investigation

Capture a repeatable moving local sequence and compare Original / MetalFX on the same decoded frames. Include abrupt alternating frames to detect previous-frame contamination, and inspect texture lifetime and command ordering. Keep perceptual sharpening artifacts, frame pacing, and cross-frame contamination as distinct possibilities until evidence separates them.

Current code inspection: conversion, scaler encoding, and final composition share one command buffer on one command queue; the intermediate texture generation is retained through GPU completion. No explicit temporal history is supplied. These facts alone do not rule out the reported artifact.

## Reopening criteria

Reopen if the artifact becomes unacceptable or a reproducible rendering defect is identified. Reproduce the reported moving-edge symptom before changing rendering behavior. Original and Integer Scaling remain available for immediate comparison.
