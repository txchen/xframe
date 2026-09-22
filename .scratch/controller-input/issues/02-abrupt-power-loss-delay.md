# Abrupt battery removal retains input until OS disconnect detection

Status: needs-info
Type: research

## Report

While moving in Palworld, removing the Xbox One controller batteries left the character moving for roughly 2–3 seconds before stopping. Reinstalling batteries and reconnecting restored input without restarting the cloud session. Normal focus-loss neutralization passed.

## Measurement — 2026-09-22

A separate read-only GameController probe was run alongside the app. It logs physical input callbacks, GCControllerDidDisconnect notification and 16 ms enumeration changes; it sends no game packets. First observation windows missed the user's action. The coordinated third run captured it (`.build/controller-disconnect-probe-3.log`):

- 10.805 s: last non-neutral callback, leftX=-1, leftY=0.41.
- 15.853 s: OS disconnect notification and framework-generated neutral callback.
- 15.861 s: device disappears from GCController.controllers().
- 25.716 s: reconnected controller appears.

The 5.048 s interval starts at the last changed input, NOT a timestamp of physical battery removal. It is not a measured power-loss-to-disconnect time. The app's polling interval cannot explain this trace's multi-second interval before the framework reported neutral/disconnection; enumeration followed the OS notification in 8 ms. This supports delayed OS detection as a contributor but does not establish precise Bluetooth timeout settings or quantify network/host delay.

Do not introduce a no-value-change timeout: a legitimate held stick may remain unchanged. No production controller behavior was changed based on this trace. Precise end-to-end latency improvement would require a physical power-loss timestamp, input packet timing and host response correlation.

[Apple disconnect notification documentation](https://developer.apple.com/documentation/gamecontroller/gccontrollerdiddisconnectnotification) defines the notification after disconnect; it does not promise a detection deadline.
