# Controller input protocol reference

Status: research complete; no live transport or physical-controller validation.

## Evidence and scope

Inspected the local XStreaming checkout at commit `383e19d324f2d3029d1c304752f4d38a9360bb95`. The findings below describe that implementation, not a Microsoft protocol guarantee. The initial XFrame slice should be a pure encoder and immutable normalized state with offline tests; controller discovery, live sending, and rumble remain separate acceptance work.

Primary sources, pinned to the inspected revision:

- [Packet encoder](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/Packet/index.ts): header, report flags, gamepad layout, normalization, and physicality.
- [Input channel](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/Channel/Input.ts): sequence allocation, polling, initial metadata, queues, and incoming rumble.
- [Gamepad driver](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/Driver/Gamepad.ts): state polling and virtual-input handling.
- [Control channel](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/Channel/Control.ts): authorization and gamepad-added/removed messages.
- [Message channel](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/Channel/Message.ts): startup ordering after the message handshake.
- [Native input normalization](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/NativeStream.tsx#L730-L753): configurable axial deadzone and edge compensation upstream of encoding.
- [Rust input implementation](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/nano-rs/src/channels/input.rs): corroborating binary layout and ordered `input` channel with protocol `1.0`.

## Binary layout

All multibyte values are little-endian. A packet containing only one gamepad report is 38 bytes: 14-byte header, one-byte report count, and a 23-byte gamepad record. This follows the pinned packet encoder, not an inferred C struct; never serialize Swift structure memory directly.

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 2 | UInt16 report flags; gamepad-only = 2 |
| 2 | 4 | UInt32 sequence |
| 6 | 8 | IEEE-754 Float64 timestamp in milliseconds |
| 14 | 1 | UInt8 gamepad record count |
| 15 | 1 | UInt8 gamepad index |
| 16 | 2 | UInt16 button mask |
| 18, 20, 22, 24 | 2 each | Int16 left X, left Y, right X, right Y |
| 26, 28 | 2 each | UInt16 left and right triggers |
| 30, 34 | 4 each | UInt32 physical and virtual physicality masks |

The header timestamp is `performance.now()` at serialization time: monotonic elapsed milliseconds, not Unix wall-clock time. The source does not establish that a specific epoch must match the server. XFrame's existing metadata uses `CACurrentMediaTime() * 1000`; retain one consistent monotonic clock and inject timestamps into pure tests. Initial client metadata uses flag 8, sequence 0, and a final UInt8 max-touch-points value, for 15 bytes. The reference increments sequence before each nonempty data packet, so the first gamepad data packet is sequence 1. UInt32 serialization gives modulo-2^32 wire values; deliberate wrapping in Swift avoids overflow traps. No sequence acknowledgement/retransmission semantics are established here. Sources: packet encoder and input channel above.

The source drains at most 29 records (`splice(0, size - 1)` with size 30), warns at 30, and encodes record count in one byte. This is an implementation convention, not evidence that the service accepts arbitrary 255-record packets. A one-controller/one-record encoder is sufficient for the initial slice. Reference polling defaults to 62.5 Hz; this is not proof of a required service rate. Sources: input channel and driver above.

## Buttons and physicality are different masks

| Input | Button mask | Physicality mask |
| --- | --- | --- |
| Nexus | 0x0002 | 0x00000400 |
| Menu | 0x0004 | 0x00000010 |
| View | 0x0008 | 0x00000020 |
| A / B / X / Y | 0x0010 / 0x0020 / 0x0040 / 0x0080 | 0x00001000 / 0x00002000 / 0x00004000 / 0x00008000 |
| D-pad up / down / left / right | 0x0100 / 0x0200 / 0x0400 / 0x0800 | 0x00000001 / 0x00000002 / 0x00000004 / 0x00000008 |
| Left / right shoulder | 0x1000 / 0x2000 | 0x00000100 / 0x00000200 |
| Left / right thumb click | 0x4000 / 0x8000 | 0x00000040 / 0x00000080 |
| Left / right trigger | Separate analog values | 0x00010000 / 0x00020000 |
| Left stick X and Y | Separate analog values | 0x00040000 and 0x00080000 |
| Right stick X and Y | Separate analog values | 0x00100000 and 0x00200000 |

The default physicality calculation flags both axes of a stick when its vector has nonzero magnitude. It flags triggers when nonzero, and buttons when truthy. Explicit finite physicality overrides are accepted; virtual physicality otherwise defaults to zero. Do not confuse these masks or infer that physicality is a constant device-capability mask. Source: packet encoder above.

## Normalization boundaries

For finite values, the reference maps axes by truncating `value * 32767` toward zero and clamping to `[-32767, 32767]`; it never emits -32768. It negates each Y axis before this conversion. Triggers are truncated after scaling by 65535 and clamped to `[0, 65535]`. Consequently +0.5 axis = 16383, -0.5 axis = -16383, and 0.5 trigger = 32767. Source: packet encoder above.

XStreaming's upstream input convention and the future macOS GameController adapter must be distinguished. Do not blindly negate GameController Y twice: define whether XFrame state is already wire-oriented or browser-oriented and test the adapter separately. The reference native path applies configurable per-axis deadzone/rescaling and optional edge compensation before encoding; none of that belongs implicitly in the wire codec. Sources: native normalization, driver, and packet encoder above.

Recommended XFrame safety policy (not claimed as server behavior): sanitize NaN/infinite analog values to neutral, clamp finite values before integer conversion, derive physicality from sanitized values, and use immutable snapshots so queued press/release states cannot alias mutable state. The reference driver queues its mutable shadow object, so copying its queue mechanics directly would not be a sound model for Swift tests.

## Golden packets

These bytes were generated by executing the pinned TypeScript packet encoder with Node 24.2.0 `stripTypeScriptTypes(..., {mode: "transform"})`, importing the transformed source in memory, and substituting `performance.now()` = 1000. No network or game session was used. Both gamepad fixtures use sequence 1, index 0, one record, all axes/triggers zero, default physicality calculation, and no metadata/pointer records.

Neutral, 38 bytes:

```text
02 00 01 00 00 00 00 00 00 00 00 40 8f 40 01 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00
```

A pressed, 38 bytes (button mask 0x0010; physicality 0x00001000):

```text
02 00 01 00 00 00 00 00 00 00 00 40 8f 40 01 00
10 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10
00 00 00 00 00 00
```

Initial metadata, sequence 0, zero touch points, 15 bytes:

```text
08 00 00 00 00 00 00 00 00 00 00 40 8f 40 00
```

These demonstrate parity with the reference implementation, not host acceptance or real-controller behavior.

## XFrame integration boundary and unresolved behavior

At research time, `Sources/XFrame/Streaming/CloudVideoConnection.swift` creates ordered `input`/`1.0`, waits for the message handshake acknowledgement, then sends only client metadata. It does not advertise a gamepad, send state reports, or parse incoming rumble. Keep those properties unchanged for the pure-encoder preparation slice.

The reference control path sends authorization, removes gamepad 0, then adds it after 500 ms (and optionally repeats for co-op index 1). The message processor starts control and input after its handshake. This is evidence of one working sequence, not proof that the delay/reset is mandatory. Live integration needs explicit connection/disconnection, focused-window ownership, neutral release, reconnect reset, failed-send/backpressure, and cleanup decisions before claiming playable input. Sources: control/message/input channels above.

Incoming rumble begins with report flags, optional eight-byte server dimensions, then type, gamepad index, four motor percentages, UInt16 duration, UInt16 delay, and UInt8 repeat. The TypeScript parser checks for only ten remaining bytes but reads eleven including type/index; do not copy that bound. It also ignores the parsed controller index and passes `startDelay: 0` separately from `delayMs`. Supported native motor capabilities, scheduling/repeat semantics, index routing, and cancellation on teardown remain unverified. Rumble is out of scope for the encoder and should require its own bounded parser and real-device validation. Source: input channel above.

## Offline acceptance groundwork

Test exact neutral/A/metadata bytes; each button's independent mask; all axes at -1, -0.5, 0, 0.5, 1; trigger endpoints and truncation; out-of-range/NaN/infinite sanitization; stick physicality pairs; no reserved bits; release-to-neutral; and sequence wrapping. An eventual scheduler should also test immutable press/release ordering, reconnect sequence reset, cancellation, and neutralization without constructing a WebRTC peer or sending data.
