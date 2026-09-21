# XFrame — Design & Requirements

## 1. Project Summary

**XFrame** is a native Apple-platform client for:

1. **Xbox Cloud Gaming (xCloud)**
2. **Xbox Console Remote Play / Home Streaming**

The first release focuses exclusively on **macOS** and prioritizes:

- low latency
- stable frame pacing
- native Apple hardware acceleration
- Retina-quality output
- detailed performance diagnostics
- controller-first usability

The project should be structured from day one so that an **iPhone/iPad version can be added later without rewriting the streaming core**.

XFrame is **not** intended to support PlayStation/PS5 streaming.

---

## 2. Product Goals

### 2.1 Primary goals

XFrame should provide a better native Xbox streaming experience on macOS than a browser-based xCloud client or Electron wrapper.

Key differentiators:

- Native WebRTC media pipeline
- Native hardware decode
- Metal-based rendering
- Correct Retina/backing-pixel rendering
- MetalFX spatial upscaling
- Configurable frame pacing
- Detailed live performance monitor
- Xbox Cloud Gaming support
- Xbox Console Remote Play support
- Native controller support and rumble
- Architecture ready for future iOS/iPadOS reuse

### 2.2 Non-goals for v1

The first release does **not** need:

- Linux support
- Windows support
- PS5 / PlayStation streaming
- Frame interpolation / frame generation
- AI super-resolution
- HDR processing unless it comes almost for free
- Multi-controller couch co-op
- App Store submission as a launch requirement
- Fully polished commercial-grade game-library UI before the streaming pipeline is stable

---

## 3. High-Level Architecture

XFrame should separate four concerns:

```text
Authentication / Xbox APIs
          |
          v
Streaming Session Providers
     /                 \
 xCloud              Xbox Home
     \                 /
          Native WebRTC
               |
        +------+------+
        |             |
      Audio         Video
                       |
               Hardware Decode
                       |
                Frame Pacer
                       |
             Metal Render Pipeline
                       |
           Post-Processing Pipeline
                       |
                  Presentation
```

Two session sources should be treated as first-class features:

```text
XCloudSessionProvider
XboxHomeSessionProvider
```

They differ in authentication/session establishment, but should converge into the same downstream pipeline as early as possible.

---

## 4. Technology Stack

### 4.1 Recommended macOS stack

Use native Apple technologies.

```text
Language:
- Swift
- Objective-C++ / C++ only where needed for libwebrtc or low-level bridging

UI:
- SwiftUI for ordinary application UI
- AppKit for platform-specific window/input behavior

Streaming:
- Native libwebrtc

Video:
- VideoToolbox / libwebrtc hardware decode
- CoreVideo
- CVPixelBuffer / IOSurface
- CVMetalTexture

Rendering:
- Metal
- MTKView or CAMetalLayer

Upscaling:
- MetalFX Spatial Upscaler

Controllers:
- GameController.framework

Audio:
- Native WebRTC audio path and/or AVAudioEngine as appropriate
```

---

## 5. UI Architecture

Do **not** enforce either a pure-SwiftUI or pure-AppKit application.

Use a hybrid architecture.

### 5.1 SwiftUI responsibilities

SwiftUI is suitable for:

- login
- game library
- console selection
- xCloud game selection
- settings
- toggles/sliders
- diagnostics panels
- account UI
- ordinary dialogs
- performance monitor UI

### 5.2 AppKit responsibilities

Use AppKit when macOS-specific control is required:

- NSWindow management
- full-screen transitions
- titlebar/window customization
- keyboard focus / first responder
- mouse hiding/capture
- keyboard shortcuts
- menu commands
- specialized panels/overlays
- multi-display behavior
- precise display integration

### 5.3 Video view

SwiftUI must **not** participate in the per-frame video hot path.

Preferred design:

```text
SwiftUI
   |
NSViewRepresentable
   |
MTKView / CAMetalLayer
   |
MetalRenderer
```

The renderer owns frame presentation independently of SwiftUI layout updates.

---

## 6. Existing Open-Source Reference Projects

XFrame should use the following as **behavior/protocol references**, not as embedded UI frameworks.

### 6.1 Geocld/XStreaming

Repository:

https://github.com/Geocld/XStreaming

Useful areas:

- Microsoft/Xbox authentication behavior
- Xbox APIs
- xCloud session creation
- Xbox Home Streaming
- SDP/ICE exchange
- WebRTC behavior
- controller packet format
- rumble/control data channels
- system messages
- mobile-native integration patterns
- Android native renderer
- FSR implementation

Important observation:

XStreaming already supports both:

- Xbox Cloud Gaming
- Xbox One / Series S / Series X home streaming

It also already demonstrates:

- WebView renderer
- Native renderer
- GPU post-processing
- FSR 1

### 6.2 XStreamingDesktop

Repository:

https://github.com/Geocld/XStreamingDesktop

Useful as a reference for:

- desktop workflow
- xCloud flow
- settings
- performance UI
- controller handling
- current user experience

Do **not** reuse its Electron/Nextron architecture.

### 6.3 Moonlight

Repository:

https://github.com/moonlight-stream/moonlight-qt

Moonlight is an important architectural reference for:

- frame pacing
- shallow frame queues
- decoder scheduling
- renderer abstraction
- hardware decode
- performance telemetry
- dropped-frame statistics
- latency-first design

Do not copy Moonlight's protocol stack; use it as a streaming-client implementation reference.

---

## 7. Shared Core and Future iOS Support

Although v1 is macOS-only, code organization must allow an iOS/iPadOS client later.

Suggested structure:

```text
XFrame/
  Shared/
    Auth/
    XboxAPI/
    Streaming/
    WebRTC/
    Protocol/
    FramePacing/
    Telemetry/
    ControllerProtocol/
    VideoPipeline/
    PostProcessing/

  macOS/
    App/
    Views/
    Windowing/
    Input/
    Display/
    Renderer/

  iOS/                 # future
    App/
    Views/
    TouchInput/
    ExternalDisplay/
```

Shared Apple components should include as much of the following as possible:

- Xbox authentication
- xCloud APIs
- Xbox Home Streaming APIs
- WebRTC signaling
- session state machines
- controller protocol
- frame pacing
- telemetry
- Metal rendering core
- post-processing interfaces

Platform-specific layers should contain:

#### macOS

- AppKit windowing
- mouse/keyboard handling
- macOS display APIs
- full-screen behavior

#### iOS/iPadOS — future

- UIKit/SwiftUI lifecycle
- touch input
- orientation
- external display
- iPhone/iPad-specific controller UX

A future target use case is:

```text
iPhone
  + Xbox controller
  + USB-C/HDMI external display
  -> Xbox Cloud Gaming / Xbox Remote Play
```

The phone may eventually act as a secondary control/status screen while the game renders to the external display.

This is a future capability, not a v1 requirement.

---

## 8. Streaming Sources

### 8.1 Xbox Cloud Gaming

Requirements:

- Microsoft/Xbox authentication
- obtain required xCloud tokens
- browse or launch supported games
- establish xCloud session
- SDP negotiation
- ICE negotiation
- WebRTC media tracks
- WebRTC data channels
- clean session shutdown
- reconnect/error handling

### 8.2 Xbox Console Remote Play

Requirements:

- discover/list consoles associated with account
- obtain xHome/Home Streaming credentials
- select console
- create home streaming session
- poll provisioning state
- SDP negotiation
- ICE negotiation
- WebRTC connection
- controller input
- rumble
- clean session shutdown

Home streaming should use the same media/render pipeline as xCloud after WebRTC establishment.

---

## 9. Session Provider Abstraction

Use a clean session provider interface.

Example conceptual API:

```swift
protocol StreamingSessionProvider {
    func prepare() async throws
    func start() async throws -> StreamingConnection
    func stop() async
}
```

Implementations:

```text
XCloudSessionProvider
XboxHomeSessionProvider
```

The rest of the application should not care whether frames came from Microsoft's datacenter or a LAN Xbox console.

---

## 10. WebRTC Layer

Use native libwebrtc.

Responsibilities:

- PeerConnection lifecycle
- SDP offer/answer
- ICE candidates
- media track callbacks
- data channels
- WebRTC statistics
- session keepalive
- failure diagnostics

Do not render video using browser `<video>` or WebView.

The main reason to build XFrame is to own the native media/render pipeline.

---

## 11. Video Decode Pipeline

Target pipeline:

```text
WebRTC
   |
compressed video
   |
VideoToolbox hardware decode
   |
CVPixelBuffer / IOSurface
   |
CVMetalTexture
   |
Metal
```

Requirements:

- verify hardware decode
- avoid CPU pixel conversion
- avoid per-frame GPU -> CPU readback
- use zero-copy or minimal-copy paths wherever possible
- expose decode timing to telemetry
- keep decoded frame queues shallow

---

## 12. Retina and Display Resolution Handling

macOS UI coordinates and video rendering coordinates must be treated separately.

Example:

```text
MacBook display:
Physical backing pixels: 3456 x 2234
Logical UI size at 2x:   1728 x 1117 points
```

UI layout uses **points**.

Video rendering uses **backing pixels**.

Never use logical SwiftUI/AppKit size as the final video render resolution.

The renderer should query the actual:

```text
MTKView.drawableSize
```

or equivalent backing pixel dimensions.

---

## 13. 1080p Source on MacBook Retina

Typical xCloud input:

```text
1920 x 1080
```

Example MacBook backing resolution:

```text
3456 x 2234
```

The stream is 16:9 while the MacBook panel is not.

Default behavior must preserve aspect ratio.

Example:

```text
1920 x 1080
    |
MetalFX Spatial
    |
3456 x 1944
    |
centered inside
3456 x 2234 drawable
```

Approximate black bars:

```text
(2234 - 1944) / 2 ~= 145 px top/bottom
```

Fractional scaling is normal.

Do **not** require integer ratios.

Examples such as 1.5x, 1.8x, and 1.63x are valid.

---

## 14. Display Modes

Support:

### Aspect Fit — default

- preserve complete image
- no distortion
- black bars where necessary

### Aspect Fill

- preserve aspect ratio
- crop edges
- explicit user choice

### Stretch

- optional
- not recommended
- never default

---

## 15. MetalFX Spatial Upscaling

MetalFX Spatial should be a first-version feature.

Pipeline:

```text
Decoded 1080p Frame
       |
       v
Metal Texture
       |
       v
MetalFX Spatial Upscale
       |
       v
Optional Sharpening
       |
       v
Retina Drawable
```

Reasons:

- xCloud frequently supplies 1080p-class output
- Retina panels are much higher resolution
- spatial upscaling does not need motion vectors
- spatial upscaling does not need depth
- no need to wait for future frames
- latency cost is small
- GPU cost should be low on modern Apple Silicon

Performance monitor must separately measure:

- upscale GPU time
- sharpening GPU time
- total render time

Quality options can initially be:

```text
Upscaling:
- Off
- Bilinear
- MetalFX Spatial
- MetalFX Spatial + Sharpen
```

---

## 16. Frame Pacing

Frame pacing is a core feature.

Do not immediately display every frame as soon as decoding finishes.

Pipeline:

```text
WebRTC
   |
decoder
   |
very shallow decoded-frame queue
   |
FramePacer
   |
Metal Renderer
   |
Display
```

The FramePacer should decide whether to:

- present next frame
- repeat previous frame
- drop stale frame

The queue must never grow without bound.

For streaming, increasing latency is generally worse than occasionally dropping a stale frame.

---

## 17. Frame Pacing Modes

Expose three user-facing modes.

### 17.1 Lowest Latency

Goal:

- minimize additional buffering

Behavior:

- render decoded frame ASAP
- aggressively drop stale frames
- minimal queue depth

Best for:

- FPS
- fighting games
- latency-sensitive games

### 17.2 Balanced — default

Goal:

- smooth network jitter without meaningfully increasing latency

Behavior:

- maintain a shallow adaptive queue
- roughly up to one source-frame interval
- align output to display timing
- drop frames when queue starts accumulating

This should be the default.

### 17.3 Smoothest

Goal:

- prioritize visual smoothness

Behavior:

- allow deeper buffering
- tolerate additional latency
- reduce visible drops

Suitable for:

- RPG
- turn-based games
- slower games

Do not allow unlimited queue growth.

---

## 18. Adaptive Jitter Buffer

Balanced mode should use an adaptive buffer rather than a fixed delay.

Conceptual behavior:

```text
Stable network:
target buffer ~4-8 ms

Moderate jitter:
target buffer ~8-16 ms

High jitter:
target buffer may approach one frame interval
```

For a 60fps stream:

```text
one frame ~= 16.67 ms
```

Balanced should generally avoid exceeding approximately one frame of added buffering.

Smoothest may optionally allow ~2 frames.

Lowest Latency should stay close to zero.

---

## 19. Display Refresh Interaction

The FramePacer should use real display timing rather than a generic software timer.

Do not schedule presentation using a simple timer loop.

Use native display/presentation timing.

### 60fps source on 120Hz display

Ideal cadence:

```text
Frame A -> refresh 1,2
Frame B -> refresh 3,4
Frame C -> refresh 5,6
```

### 30fps source on 120Hz display

Ideal cadence:

```text
Frame A -> refresh 1,2,3,4
Frame B -> refresh 5,6,7,8
```

The renderer must dynamically handle:

- 30fps content
- 60fps content
- variable transport behavior

---

## 20. Source FPS vs Transport FPS

Do not assume:

```text
transport FPS == unique game FPS
```

A 30fps game may be carried by a 60fps transport cadence using repeated frames.

Example:

```text
Game:
A B C D       (30 unique fps)

Transport:
A A B B C C   (60 frame cadence)
```

This matters for:

- performance statistics
- frame pacing
- future frame interpolation

The telemetry subsystem should expose:

```text
Transport / decoded FPS
Estimated unique-content FPS
Presented FPS
```

If possible, estimate unique-content cadence using:

- timestamps
- frame identity/reference behavior
- lightweight frame-difference analysis

Do not perform expensive full-frame comparison on CPU.

---

## 21. Future Frame Interpolation

Frame interpolation is explicitly **post-v1**.

Potential target:

```text
30fps game
-> frame interpolation
-> 60fps output
```

RDR2 on Xbox is a useful future test case.

Do not design the interpolation pipeline under the assumption that xCloud transport FPS equals source-game FPS.

Before interpolation:

```text
A A B B C C
```

must be recognized as approximately:

```text
A B C
```

unique-content cadence.

Potential future modes:

```text
Interpolation:
- Off
- Low Latency
- Quality
```

Interpolation must remain optional.

Latency and artifacts must be measured.

---

## 22. Performance Monitor

The performance monitor is an **MVP requirement**, not merely a developer tool.

Streaming problems are difficult to diagnose from average FPS alone.

The monitor should help identify whether a problem originates from:

- network
- WebRTC
- jitter buffer
- decoder
- frame queue
- frame pacing
- GPU post-processing
- Metal rendering
- presentation/vsync

---

## 23. Compact Performance Overlay

Example:

```text
STREAM   1920x1080 H.264  59.9 fps
SOURCE   ~30.0 unique fps
OUTPUT   3456x1944        59.9 fps

NET      RTT 24 ms
         jitter 3.1 ms
         loss 0.0%

VIDEO    decode 1.2 ms
         late 0
         dropped 0

QUEUE    7.4 ms
         0.44 frames

GPU      upscale 0.6 ms
         sharpen 0.2 ms
         render 0.4 ms

PACE     avg 16.7 ms
         p95 17.4
         p99 21.0
```

---

## 24. Performance Graphs

Provide an expanded diagnostics view with rolling history.

Recommended history:

```text
30-60 seconds
```

Graphs:

- incoming/decoded FPS
- estimated unique-content FPS
- presented FPS
- frame interval / frame time
- RTT
- jitter
- packet loss
- bitrate
- decode time
- decoded queue depth
- frame queue latency
- post-process GPU time
- render/present time

Mark events such as:

- dropped frame
- repeated frame
- late frame
- reconnect
- jitter spike

---

## 25. Frame-Time Metrics

Average FPS is not sufficient.

For a nominal 60fps stream:

```text
target interval ~= 16.67 ms
```

Track:

- p50 frame interval
- p95
- p99
- maximum
- frames > 25 ms
- frames > 33 ms

For 30fps:

```text
target interval ~= 33.33 ms
```

Use source cadence when interpreting pacing metrics.

---

## 26. Telemetry Architecture

Telemetry must be independent from the UI.

Suggested design:

```text
TelemetryCollector
     |
     +-- WebRTC stats
     +-- decoder metrics
     +-- FramePacer metrics
     +-- renderer metrics
     +-- display metrics
     |
RingBuffer / History
     |
     +-- Compact Overlay
     +-- Diagnostics Graphs
     +-- Export
```

Requirements:

- low-contention data structures
- UI must never block render/media threads
- allow JSON/CSV export
- provide "Copy Diagnostics"
- redact sensitive tokens
- keep protocol logs separate from performance samples

---

## 27. Controller Support

Use:

```text
GameController.framework
```

MVP:

- one controller
- sticks
- triggers
- A/B/X/Y
- shoulders
- D-pad
- Menu/View
- stick-click
- Xbox/guide button where possible
- rumble

Do not rely on browser Gamepad APIs.

---

## 28. Multi-Controller Support — Future

XStreaming's protocol structures include gamepad index concepts, so future multi-controller support should be possible.

Potential mapping:

```text
Controller 1 -> GamepadIndex 0
Controller 2 -> GamepadIndex 1
Controller 3 -> GamepadIndex 2
Controller 4 -> GamepadIndex 3
```

However:

- xCloud multi-controller behavior must be experimentally verified
- Xbox Home Streaming may behave differently
- not a v1 requirement

Future use case:

```text
MacBook / Mac mini
+ TV
+ multiple Xbox controllers
-> couch co-op
```

---

## 29. Audio

Goals:

- low latency
- stable output
- minimal buffering
- synchronized enough for games without forcing video latency higher

Avoid introducing large audio buffers just to achieve perfect media-player-style synchronization.

Game streaming prioritizes responsiveness.

---

## 30. Error Handling and Diagnostics

Never fail with only a blank screen.

Surface useful states:

```text
Authenticating
Requesting xCloud token
Creating session
Provisioning
Creating SDP
Waiting for SDP answer
Exchanging ICE candidates
Connecting WebRTC
Receiving video
Receiving audio
Connected
Reconnecting
Failed
```

Debug mode should expose:

- session state
- negotiated codec
- video resolution
- SDP/ICE state
- selected server/region if known
- WebRTC stats
- decoder status

Tokens and credentials must be redacted.

---

## 31. Security

Requirements:

- store long-lived secrets/tokens using Keychain
- never log bearer tokens
- redact tokens from diagnostics exports
- do not embed credentials in source code
- validate TLS normally
- do not disable certificate verification
- isolate authentication code from UI code

---

## 32. Mac App Distribution

XFrame should support direct distribution first.

Recommended initial distribution:

```text
Developer ID signed
+ notarized
+ DMG
```

Architecture should not intentionally prevent future Mac App Store submission.

Avoid:

- private Apple APIs
- downloading executable code at runtime
- assumptions that require disabling sandbox permanently

However, App Store submission is not a v1 blocker.

---

## 33. Performance Requirements

### 33.1 Video

Target:

```text
1080p60 source
-> native hardware decode
-> stable native rendering
```

Requirements:

- no routine CPU pixel conversion
- no frame readback
- no unbounded queue
- drop stale frames when necessary
- track decode latency
- track queue latency
- track post-process GPU time

### 33.2 Upscaling

1080p -> Retina spatial upscale should remain inexpensive.

Performance monitor should verify this instead of relying on assumptions.

Target engineering goal:

```text
Upscale + sharpening should consume only a small fraction
of a 16.67 ms 60fps frame budget.
```

Do not hardcode a guaranteed millisecond value before benchmarking.

---

## 34. Threading Model

Suggested logical separation:

```text
Main/UI Thread
    |
    +-- SwiftUI/AppKit

WebRTC Thread(s)
    |
    +-- signaling
    +-- network
    +-- media callbacks

Decode
    |
    +-- VideoToolbox/libwebrtc

Frame Pacer
    |
    +-- shallow frame queue
    +-- timeline decisions

Metal Render Thread / Display Callback
    |
    +-- texture import
    +-- upscale
    +-- post-process
    +-- present

Telemetry
    |
    +-- low-overhead sampling
```

Do not perform heavy telemetry/UI work on media/render threads.

---

## 35. Suggested Modules

```text
XFrame
├── App
│   ├── XFrameApp
│   ├── Navigation
│   └── Settings
│
├── Shared
│   ├── AuthService
│   ├── XboxApiClient
│   ├── Protocol
│   ├── StreamingSession
│   ├── XCloudSessionProvider
│   ├── XboxHomeSessionProvider
│   ├── WebRTCTransport
│   ├── FramePacer
│   └── Telemetry
│
├── macOS
│   ├── WindowController
│   ├── DisplayManager
│   ├── KeyboardManager
│   └── MouseManager
│
├── Video
│   ├── VideoReceiver
│   ├── MetalVideoView
│   ├── MetalRenderer
│   └── PostProcessing
│       ├── SpatialUpscaler
│       ├── MetalFXSpatialUpscaler
│       ├── Sharpen
│       └── ColorAdjust
│
├── Audio
│   └── AudioReceiver
│
├── Input
│   ├── ControllerManager
│   └── RumbleManager
│
└── Tests
    ├── ProtocolTests
    ├── SessionTests
    ├── FramePacerTests
    └── InputPacketTests
```

---

## 36. MVP Requirements

The first usable release must provide:

- Microsoft/Xbox login
- persistent authenticated session
- Xbox Cloud Gaming connection
- Xbox Console Remote Play connection
- one-controller support
- rumble if reasonably straightforward
- native WebRTC
- native hardware video decode
- native audio
- Metal video rendering
- correct Retina rendering
- Aspect Fit
- full-screen mode
- MetalFX spatial upscale
- optional sharpening
- configurable frame pacing
- Balanced pacing as default
- 30fps and 60fps cadence support
- performance overlay
- rolling performance graphs
- clean disconnect
- actionable failure messages

---

## 37. Recommended Development Milestones

### M0 — Research / protocol extraction

- audit XStreaming auth
- audit xCloud APIs
- audit Xbox Home APIs
- document data channels
- document controller packet format
- document rumble behavior
- document session state machine

Output:

- protocol notes
- typed request/response models
- unit tests for packet encoding

### M1 — Native WebRTC proof

Build a minimal macOS application that:

- authenticates
- starts one xCloud session
- establishes native WebRTC
- receives video/audio
- logs transport stats

Do not spend time polishing UI.

### M2 — Native video presentation

Implement:

```text
WebRTC
-> VideoToolbox
-> CVPixelBuffer
-> Metal
-> MTKView/CAMetalLayer
```

Acceptance:

- stable 1080p60
- hardware decode verified
- no obvious CPU frame copies

### M3 — Input / audio / Xbox Home

Implement:

- controller input
- rumble
- native audio
- Xbox Home Streaming
- clean session lifecycle

### M4 — Frame pacing

Implement:

- Lowest Latency
- Balanced
- Smoothest
- shallow adaptive queue
- 30/60fps cadence detection
- 60Hz/120Hz display handling

### M5 — Performance monitor

Implement:

- compact overlay
- rolling graphs
- frame-time metrics
- network metrics
- queue latency
- GPU timing

### M6 — Spatial upscale

Implement:

- MetalFX Spatial
- optional sharpening
- arbitrary Retina output size
- reconfiguration on window/display changes

### M7 — Product polish

- game library UI
- console selection UX
- settings
- saved preferences
- full-screen polish
- controller navigation
- packaging/notarization

### Future — Frame interpolation

Experiment with:

```text
30 unique fps
-> optical-flow / interpolation
-> 60fps output
```

RDR2 is a good future validation target.

---

## 38. Acceptance Tests

### 38.1 xCloud

- log in
- launch game
- stable 60-minute session
- controller remains connected
- video/audio stay synchronized enough for gameplay
- no progressive latency accumulation

### 38.2 Xbox Home Streaming

- select Xbox console
- connect on LAN
- stable session
- controller input
- rumble
- reconnect after temporary network disruption

### 38.3 Retina

Test:

- arbitrary window sizes
- normal 2x Retina scaling
- full-screen
- external 4K display
- moving window between displays
- no aspect distortion
- drawable resolution updates correctly

### 38.4 Frame pacing

Test:

- stable 60fps game
- stable 30fps game
- 60Hz monitor
- 120Hz ProMotion monitor
- artificial jitter
- late frames
- packet loss

Verify queue does not accumulate indefinitely.

### 38.5 Performance monitor

Verify a synthetic render slowdown is visible as:

- increased render time
- increased frame queue latency
- late/dropped frames

Verify a network jitter spike appears separately from GPU/decode timing.

---

## 39. Key Design Principles

1. **Latency before perfection.**
2. **Never allow frame queues to grow without bounds.**
3. **Use hardware decode.**
4. **Keep video on GPU surfaces whenever possible.**
5. **SwiftUI must not be in the per-frame rendering path.**
6. **Use real display timing for pacing.**
7. **Do not confuse transport FPS with unique game FPS.**
8. **Measure everything.**
9. **MetalFX spatial upscaling is a v1 feature.**
10. **Frame interpolation is post-v1.**
11. **xCloud and Xbox Home should share the same downstream media pipeline.**
12. **macOS comes first, but shared code should be reusable on iOS.**
13. **Do not compromise macOS performance today for hypothetical Linux portability.**

---

## 40. Final Product Direction

The first XFrame release should feel like:

> A native Xbox streaming client built specifically for Apple Silicon Macs, with lower-level control than the browser, high-quality Retina output, excellent frame pacing, and diagnostics good enough to explain exactly why a stream does or does not feel smooth.

The ideal first-release pipeline is:

```text
Xbox Cloud / Xbox Console
          |
       WebRTC
          |
    Hardware Decode
          |
     Frame Pacer
          |
       Metal
          |
  MetalFX Spatial
          |
      Sharpening
          |
  Retina Presentation
```

with a live performance monitor observing every important stage.

The architecture should leave a clean path to:

```text
macOS v1
   |
   +--> iPhone / iPad
   |
   +--> external TV output
   |
   +--> multi-controller
   |
   +--> 30 -> 60 frame interpolation
```

without requiring the core streaming stack to be rewritten.

