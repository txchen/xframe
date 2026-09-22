# Veyra technology portability to macOS

Research date: 2026-09-22. Source inspection only; no downloaded implementation was built or benchmarked on XFrame's M1.

## Findings

| Technology | macOS status found | Meaning for XFrame |
| --- | --- | --- |
| FSR 3.x frame generation | An experimental Wine/GPTK integration exists in Metal FSR 4. It uses the original AMD 3.1.6 FG provider and 3.1.7 interpolation swapchain. | Evidence that it can run in a Mac game wrapper, not a ready native Metal video-interpolation library. |
| FSR 4.0.2 upscaling | Metal FSR 4 contains native Metal neural upscaling, bridged to D3D12 games. | Distinct from its DLL-based FG path; do not conflate the two. |
| FSR 3.1 upscaling | FSR3Unity supports macOS Metal through Unity shader translation. | An actual upscaling port, not evidence of a frame-generation port. Its README documents atomic-operation correctness compromises. |
| XeSS frame generation | Intel's inspected developer interface is D3D12 swapchain based. No native Metal/macOS FG port was found in this targeted search. | Not an off-the-shelf native XFrame backend; cross-vendor PC GPU support does not establish Apple GPU support. |
| Veyra GPU DIS optical flow | Veyra builds HLSL compute shaders to DXIL and integrates D3D12 resources. No native Metal version of this specific implementation was found. | Algorithm/shader port is technically plausible, but would require compute/resource/synchronization adaptation and validation. This is an engineering inference, not a completed port. |
| AMD FidelityFX optical flow | Published source is available in the FidelityFX SDK. No native Metal port was verified in this search. | Potential source-level port; publishing source does not establish a ready Mac backend. |
| DLSS NR / frame generation | Parent investigation found MLX-DLSS, an experimental native Swift MLX/Metal implementation with video-only frame generation. | Actual community port, not official NVIDIA support; requires externally supplied model weights and M1 performance remains unmeasured. |

## Primary sources

- [Metal FSR 4 repository](https://github.com/Alien4042x/metal-fsr-4): README separates native Metal FSR 4.0.2 inference from AMD FG DLL/provider, describes Wine/GPTK installation, and calls the current build dependent on a private baseline rather than reproducible from a fresh checkout. The KCD2 result is an author observation, not independent validation.
- [FSR3Unity](https://github.com/ndepoel/FSR3Unity): FSR 3.1 Upscaler for Unity, with macOS Metal support and shader translation notes.
- [Intel XeSS FG guide](https://github.com/intel/xess/blob/main/doc/xess_fg_developer_guide_english.md): D3D12 context, resource tagging and swapchain API.
- [Veyra GPU DIS integration](https://github.com/Likely7/Veyra-NRVideo/blob/main/src/guidance/GpuDisOpticalFlow.cpp) and [shader build](https://github.com/Likely7/Veyra-NRVideo/blob/main/cmake/VeyraGpuDis.cmake): D3D12 integration and HLSL-to-DXIL compilation.
- [AMD optical-flow source](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/main/Kits/FidelityFX/framegeneration/fsr3/internal/ffx_opticalflow.cpp) and [frame generation API](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/main/Kits/FidelityFX/docs/techniques/frame-interpolation-api.md).
- [MLX-DLSS](https://github.com/iamwavecut/MLX-DLSS) and [frame generation notes](https://github.com/iamwavecut/MLX-DLSS/blob/main/docs/frame-generation.md): native experimental video-only reconstruction, supplied weights, and author benchmarks; not measured here.

## Scope and caveats

Searches distinguished source-level native Metal implementations from Wine/GPTK wrappers and separated upscaling from frame generation. A search finding no verified native port does not prove none exists. None of these sources establishes real-time 1080p performance, output quality, or latency on XFrame's M1. A prototype must measure those independently.
