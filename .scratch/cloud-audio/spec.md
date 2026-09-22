# Receive-Only Game Audio

## Scope

Enable remote game audio using the bundled WebRTC native decoding, jitter buffering and macOS output. Keep the audio transceiver receive-only. Never create a local microphone/camera track, request capture permission, or send voice/chat audio. Do not copy reference clients' microphone or browser-specific AudioContext plumbing.

Provide session-independent in-memory mute and volume preferences in Cloud Games. Limit gain to 0...1 (no amplification); apply settings to tracks arriving later and replacements. Mute and zero volume disable output. End Session, cancellation and errors disable/release the remote track before peer cleanup. Changing game audio controls must not change system output volume.

Show remote track state, inbound audio packet count and accumulated audio energy. These prove reception/decoded signal, not physical audibility or A/V synchronization. Unsupported statistics must remain n/a. Audible output, mute/unmute and A/V synchronization require a human listening check; do not infer success from packet counts alone.

Controller input, microphone/chat, output-device selection, spatial audio, gain amplification and forced stereo SDP patching are out of scope.

## Verification

Test pre-track settings, mute/unmute, clamping, zero volume, invalid gain, track replacement, stop and late callbacks with an injected output adapter. Run the existing auth/video/session tests and release build. Launch the existing Fortnite preview, verify incoming audio statistics, exercise controls and confirm session cleanup. Ask the user to confirm audible sound without collecting microphone recordings.
