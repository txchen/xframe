# HDR Streaming Research (xCloud / Xbox Console Remote Play on Apple Silicon)

Updated: 2026-11-23. Status: research / feasibility baseline (SDR pipeline remains production).

## 1. Current Xbox Protocol Constraints
- **xCloud WebRTC**: Currently negotiates 8-bit SDR H.264 (`profile-level-id=42e01f` / `640c2a`) over WebRTC. Xbox Cloud Gaming web/Tizen endpoints do not yet advertise 10-bit HEVC (`H265`) or PQ/BT.2020 HDR streams over the public WebRTC signaling flow.
- **Xbox Series X Remote Play (xHome)**: Console hardware supports HDR10 locally, but the xHome WebRTC transport currently tonemaps to 8-bit SDR H.264 before encoding.
- **Implication**: Client-side HDR display output cannot recover true 10-bit HDR highlights from an 8-bit SDR stream; native HDR requires upstream 10-bit HEVC/AV1 PQ delivery.

## 2. Apple Silicon / macOS Metal HDR Pipeline Requirements (When Upstream Supports 10-bit PQ)
1. **Decoder (`HardwareH264Decoder` / future HEVC decoder)**:
   - Request `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` (`x420`) in `VTDecompressionSessionCreate` image buffer attributes when `CMFormatDescription` indicates 10-bit PQ (`kCMFormatDescriptionExtension_TransferFunction == SMPTE_ST_2084_PQ`) and `BT.2020` primaries.
   - Import planes with `.r16Unorm` (Y) and `.rg16Unorm` (CbCr) via `CVMetalTextureCacheCreateTextureFromImage`.
2. **Metal Surface & EDR**:
   - Set `CAMetalLayer.pixelFormat = .rgba16Float`, `wantsExtendedDynamicRangeContent = true`, and `colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)` (or `.itur_2100_PQ` with `CAEDRMetadata.hdr10(...)`).
   - Query `NSScreen.maximumExtendedDynamicRangeColorComponentValue` to scale PQ nits cleanly to the display's EDR headroom (MacBook Pro XDR / external HDR10 TV).
3. **Post-Processing Compatibility**:
   - `MTLFXSpatialScalerDescriptor` supports `.rgba16Float` with `.hdr` color processing mode (`colorProcessingMode = .hdr`).
   - FSR 1 EASU/RCAS and Core ML FG weights are trained/tuned for SDR `[0, 1]` perceptual space and would require PQ-domain or Reinhard tonemapped intermediate execution before returning to linear EDR.

## 3. Recommendation
- Keep the current SDR BT.601/BT.709 zero-copy NV12 path as default and do not ship fake SDR-to-HDR expansion.
- Revisit native 10-bit EDR rendering once xCloud or xHome advertises 10-bit HEVC/AV1 in SDP offers.
