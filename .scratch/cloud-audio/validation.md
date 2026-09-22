# Receive-only audio validation

Date: 2026-09-21.

## Automated checks

- All 37 tests passed, including pre-arrival preferences, mute/unmute with remembered gain, zero/invalid/out-of-range gain, replacement, shutdown and late attachment.
- Existing hardware H.264 recovery, authentication and session cleanup regressions passed.
- Release application build and local development signing passed.
- No microphone source, local audio sender or capture permission was added. The audio transceiver remains recvonly.

## Live cloud session

- Rebuilt app restored the existing file-based login without another password prompt. Automatic requested region resolved to WESTUS2.
- Fortnite produced native 1920 x 1080 hardware-decoded video and an attached remote audio track. Initial sample: 814 audio packets and 0.011 accumulated audio energy.
- The user explicitly confirmed hearing game sound on the Mac's current output device.
- Set volume to 40% and muted through Cloud Games. Renderer reported Audio Muted, Volume 40%, 1,650 audio packets, and continued video at 54.8 decode / 53.3 presentation fps with zero decode errors.
- Unmuted: renderer reported Audio Enabled at the remembered 40%, 2,276 packets, energy 0.032, 56.2 decode / 54.6 presentation fps, zero video packet loss and zero decode errors.
- Command-0 ended the session; Cloud Games visibly reported Session ended and retained the 40% setting. The implementation disables/releases audio before peer cleanup.
- No game confirmation, Epic account linking, microphone recording or system volume change was performed.

## Remaining acceptance limits

The human confirmation establishes audible output, not a precise A/V synchronization measurement. Physical silence during mute/after teardown and perceived gain changes were not separately confirmed by the user; those controls have automated adapter coverage and live state verification. Stereo forcing, device selection, controller input and microphone/chat remain out of scope.
