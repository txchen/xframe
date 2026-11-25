# xCloud WebRTC Protocol & Resolution Findings (Live Verification)

Updated: 2026-11-24. Verified live against Xbox Cloud Gaming (`v5/sessions/cloud/play`, Game Pass Ultimate account, title `ABSOLUM`) from Apple Silicon macOS using XFrame's native WebRTC 153.0.0 stack.

This document records empirically verified server behavior for XFrame and future clients (e.g., GFrame).

---

## 1. Resolution Negotiation (Live Results on `ABSOLUM`)

All five profiles below were tested with `displayInfo.dimensions = 1920×1080`, local SDP offer H.264 `a=fmtp` capped to `max-fs=8160;max-mbps=489600` (1080p60), and `dimensionschanged` sending `preferredWidth: 1920, preferredHeight: 1080, supportsCustomResolution: false`:

| `settings.osName` | `X-MS-Device-Info` `platformType` | Actual Decoded Stream Resolution |
|---|---|---|
| `macos` | `desktop` | **2560×1440** (2K) |
| `windows` | `desktop` | **2560×1440** (2K) |
| `linux` | `desktop` | **2560×1440** (2K) |
| `android` | `mobile` | **1280×720** (720p) |
| `ios` | `tablet` | **1280×720** (720p) |

### Key Takeaways
1. **xCloud ignores H.264 SDP `max-fs` / `max-mbps` and `dimensionschanged.supportsCustomResolution = false`** when selecting the initial encode resolution on 1440p-enabled Game Pass Ultimate titles.
2. Resolution selection is driven at session creation (`POST /v5/sessions/cloud/play`) by the **client tier** (`desktop` vs `mobile`/`tablet`), not by the declared pixel dimensions in `X-MS-Device-Info`.
3. For 1440p-enabled titles on Ultimate, xCloud effectively offers **two tiers**:
   - **Desktop tier** (`macos` / `windows` / `linux` / `tizen`): **1440p** (for supported titles) or **1080p** (for non-1440p titles).
   - **Mobile/Tablet tier** (`android` / `ios`): **720p** (`1280×720`, which is an exact **3× Integer Scale** on 4K `3840×2160` displays).
4. **Session re-creation cooldown**: Immediately calling `POST /v5/sessions/cloud/play` for the same `titleId` within ~3–12 s after `DELETE` can return HTTP `410 Gone` during state polling while the previous session is still tearing down on the backend.

---

## 2. `/configuration` Server Capabilities & Low-Latency Transport

Live `/configuration` `clientStreamingConfigOverrides` returned by xCloud:

```json
{
  "inputConfiguration": {
    "useUnreliableInput": true
  },
  "nqiConfiguration": {
    "consecutiveBadIntervalsForTrigger": 10,
    "decodeMsBadThreshold": 24,
    "pingMsBadThreshold": 100
  },
  "statisticsConfiguration": {
    "useQosChannel": true
  }
}
```

### Practical Implications for Low-Latency Clients (XFrame / GFrame)
1. **Unreliable / Unordered `"input"` DataChannel**:
   - The server explicitly advertises `"useUnreliableInput": true`.
   - Because Xbox input wire packets carry full controller state snapshots plus monotonic sequence numbers, configuring the `"input"` DataChannel with `isOrdered = false` and `maxRetransmits = 0` eliminates SCTP head-of-line blocking during transient uplink packet loss.
   - Keep `"control"`, `"message"`, and `"chat"` channels ordered & reliable.
2. **Independent Video & Audio Sync Groups**:
   - WebRTC logs confirm xCloud assigns video (`mid=0`, `stream_ids: 1`) and audio (`mid=1`, `stream_ids: 0`) to **separate sync groups**.
   - Audio NetEq jitter-buffer expansion therefore does not directly hold back video playout via `RtpStreamsSynchronizer`, though setting `audioJitterBufferFastAccelerate = true` and `audioJitterBufferMaxPackets = 20` still keeps audio latency tight.
3. **WebRTC Video Playout Delay**:
   - xCloud negotiates the RTP `playout-delay` extension (`http://www.webrtc.org/experiments/rtp-hdrext/playout-delay`), `abs-send-time`, `transport-wide-cc`, and `flexfec-03`.
   - `WebRTC-ForcePlayoutDelay` (`min_ms:0,max_ms:0`) confirms `min_playout_delay_ms: 0` in `VideoReceiveStream2`, while WebRTC's internal `render_delay_ms` remains `10 ms` unless overridden.
4. **H.264 Keyframe Recovery**:
   - xCloud sends H.264 IDR frames without inline SPS/PPS (`SPS: 0, PPS: 0`) after initial parameter sets; WebRTC treats them as keyframes when `WebRTC-SpsPpsIdrIsH264Keyframe` is disabled (default). Hardware decoders must retain cached SPS/PPS across IDR recoveries.
