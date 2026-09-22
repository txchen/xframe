# Xbox HEVC source investigation

Checked 2026-09-22. Source inspection only; no live Xbox/cloud SDP or decoded stream was captured.

## XStreaming

- Android/main HEAD `383e19d324f2d3029d1c304752f4d38a9360bb95`: the H265 row is commented out. Available choices are Auto and H264 profiles. [Settings](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/common/settings/display.ts#L100-L120).
- Native stream codec selection only rewrites H264 payload priority in the offer. This is not a HEVC enablement path. [NativeStream](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/NativeStream.tsx#L1718-L1818).
- iOS branch HEAD `e54dc280c7246c3b735e0c2583484504d81bdb9c`: **an active H265 UI option exists**, using `video/H265`. [Settings](https://github.com/Geocld/XStreaming/blob/e54dc280c7246c3b735e0c2583484504d81bdb9c/src/common/settings/display.ts#L60-L76).
- However, tracing the actual iOS bundled player shows the option is handed to generic `setCodecPreferences`, then `_setCodec` checks local `RTCRtpReceiver.getCapabilities('video')` and implements SDP reordering only inside an H264 branch. Unsupported MIME types return the original offer; supported non-H264 MIME types fall through without a return, while the caller assigns the result to `offer.sdp`. Thus the UI is not evidence of working HEVC negotiation; static inspection suggests this path is incomplete. [Actual iOS player bundle, line 68](https://github.com/Geocld/XStreaming/blob/e54dc280c7246c3b735e0c2583484504d81bdb9c/ios/XStreaming/Resources/stream/assets/index-BYf5eIF2.js#L68). Search this minified line for `_setCodec(o,s,c)` and `c.sdp=this._setCodec`.

## XStreaming desktop

HEAD `0e4b661254cdacba2afcecad5fd9ff3068f91beb` exposes Auto and H264 profiles. [Settings](https://github.com/Geocld/XStreaming-desktop/blob/0e4b661254cdacba2afcecad5fd9ff3068f91beb/renderer/common/settings.ts#L147-L167). It passes preferences to `xstreaming-player`. [Call site](https://github.com/Geocld/XStreaming-desktop/blob/0e4b661254cdacba2afcecad5fd9ff3068f91beb/renderer/pages/%5Blocale%5D/stream.tsx#L619-L628).

The Linux Chromium startup flags include `PlatformHEVCDecoderSupport`. This enables a local browser decoding capability, not an Xbox encoder setting or proof of successful HEVC streaming. [Flag](https://github.com/Geocld/XStreaming-desktop/blob/0e4b661254cdacba2afcecad5fd9ff3068f91beb/main/application.ts#L58).

## Better xCloud

Inspected HEAD `f8397043f6d2148d2345d508902a38c69cf1ee20`. [SDP selection](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/utils/sdp.ts#L1-L53) reprioritizes H264 profiles (4d/420/42e), and [stream settings](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/utils/settings-storages/global-settings-storage.ts#L16-L68) filter `video/h264`. This offers no demonstrated HEVC negotiation path. The [xHome resolution override](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/utils/xhome-interceptor.ts#L138-L150) changes resolution/client headers, not video codec. Android wrapper public repository does not expose the implementation, so no codec conclusion is inferred from it.

## PS5 comparison

The [chiaki-ng configuration documentation](https://streetpea.github.io/chiaki-ng/setup/configuration/#hdr-high-dynamic-range) explicitly provides an H265 HDR (PS5 only) option. This confirms a real PS5 feature, separate from Xbox negotiation.

## Conclusion and verification boundary

These implementations do not supply a verified, reusable route to Xbox HEVC. This does not establish that every Microsoft client or server permanently lacks HEVC. A definitive test requires a client that can actually receive H265, an explicit H265 offer, the returned answer SDP, and inbound RTP codec statistics (ideally decoded frames) for xCloud and console separately. The iOS H265 menu alone is insufficient. PS5 remote play HEVC support is a separate sender/protocol capability and cannot establish Xbox support.
