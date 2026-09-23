# Xbox Console Remote Play — working spec

Status: implementation candidate built; physical Series X acceptance pending.

## Confirmed decisions

- The first live acceptance console is an Xbox Series X.
- A Local Console Session carries game video, audio, and controller input over the LAN between the Mac and Xbox. Microsoft online sign-in and session setup may still be used. Do not silently fall back to an Internet media relay when a local media path cannot be established.
- Xbox Sign-in, Cloud Gaming Access, and Console Access are separate. Lack of Cloud Gaming Access must not block a Local Console Session on an accessible console.
- List all Associated Consoles for the signed-in profile, including ones outside the current LAN. Show local availability clearly and allow a Local Console Session only on a Locally Available Console.
- For a console in standby, present an explicit **Wake Console** action before connection. Never wake it merely because the user opened the list or selected the console. Verify that it becomes locally available before starting a session.
- Wake Console and Connect are two separate user actions. A successful wake changes the available action to Connect; it does not automatically start streaming.
- Disconnect Local Console Session stops XFrame's audio, video, and controller connection and ends its remote-play session. It leaves the Series X powered on and does not quit or change the game. Power control is a separate action.
- XFrame owns at most one Active Streaming Session across Cloud Gaming and Local Console Sessions. Connecting to a console while a cloud session is active must prompt the user to end the cloud session explicitly and wait for confirmed cleanup; it must not implicitly tear down the cloud session.
- On a brief LAN interruption, attempt Local Session Recovery for a bounded interval using the original session. Never wake the console or relaunch a game as part of recovery. After the limit, stop automatic attempts and offer a user-initiated retry. Reuse the existing cloud stream's 15-second recovery budget unless live Series X evidence requires a change.
- First live media target: stable 1920 × 1080 output at up to 60 received frames per second, with audible game audio and responsive controls. Report received stream FPS separately from the game's render FPS. Higher resolutions are outside this first acceptance target.
- Controller rumble is required for this increment. Support one compatible GameController device without a model-specific product gate, including Xbox One and PS4 / DualShock 4 controllers. A live Series X game must send rumble and a connected controller must physically vibrate; parsing a packet or starting a haptic engine alone is insufficient. Record which devices were actually tested and do not extend one device's live result to another.

## Existing product scope

The [roadmap](../roadmap/spec.md) calls for console discovery/list, wake, session establishment, reuse of the native audio/video/input pipeline, and real-console acceptance. The [requirements](../../xframe_requirement.md) also call for rumble and recovery after temporary network disruption.

## Implementation approach

- Keep Xbox Sign-in available after a failed Cloud Gaming authorization check. Obtain Console Access separately; show independent errors and eligibility for Cloud Gaming and console play.
- Add a **Consoles** destination to the existing library shell. List Associated Consoles with console name/model, reported power state, and independently checked LAN availability. A service-reported `On` state alone must not be labeled locally available. Show **Wake Console** for a standby console and wait for local availability; then show **Connect**. If the console is outside the LAN or remote features are disabled, explain the condition without offering an Internet stream.
- Use a home-session provider for xHome authentication, console listing, session creation, signaling, keepalive, and deletion. Route its WebRTC media and controller channels through the existing native audio, VideoToolbox, Metal, frame-pacing, and input pipeline. Keep one shared session owner across cloud and home flows. Request the baseline 1080p profile without treating a requested setting as a received resolution.
- Enforce the LAN requirement on the selected WebRTC transport, not only on the account console list. Inspect the selected ICE candidate pair and its route after connection and when ICE changes. Stop the session if the media/control route is relayed, nonlocal, or cannot be established as local. Keep raw addresses and tokens out of user-facing diagnostics.
- Reuse the existing explicit controller and keyboard enablement, focus ownership, neutral release, audio volume/mute, scaling, frame-pacing, and HUD behavior. Do not apply cloud region or cloud game-language settings to a console session by accident. Decode bounded incoming rumble messages and drive supported controller actuators without model-specific product restrictions. Show a clear unsupported-haptics state when the current macOS controller connection exposes no haptic actuator.
- On Disconnect, stop local audio/video/input immediately, request home-session deletion, and retain cleanup ownership until the service confirms it. Offer cleanup retry on failure and do not claim the session ended prematurely. Never send a power-off command as part of Disconnect. A Mac sleep ends the session; waking the Mac never wakes the Xbox or starts a stream.
- Apply the current 15-second recovery budget to brief LAN interruptions, with neutral input while transport is unavailable. After recovery expires, close/clean up the old session and require an explicit retry. A retry never launches a game.

## Baseline constraints addressed

The baseline `XboxAccount.verifyCloud` treated failed xCloud authorization as failed sign-in, and `CloudLibraryView` showed the library only when `hasCloudAccess` was true. The implementation now keeps Xbox identity, console access, and cloud access independent; associated consoles can still be listed with an Xbox sign-in when xHome authorization is unavailable.

The baseline `CloudLibrary`, `CloudService`, and `CloudVideoConnection` mixed cloud-specific lifecycle and reusable media/input responsibilities. A shared `SessionServing` lifecycle and home provider now reuse the same owner, rendering, input, audio, and cleanup path.

## Acceptance

- Static/build verification: separate account capabilities, associated-console list and availability state, explicit two-click Wake Console then Connect, one-session guard, home session lifecycle/cleanup retry, LAN-path rejection, existing input ownership, bounded rumble decoding, and no power-off on Disconnect.
- Live Series X verification: sign in, list the console, wake from standby by explicit click, connect on the same LAN with verified local transport, receive stable 1080p video at up to 60 fps with audible game audio, control a game, observe physical rumble, and disconnect while the console and game remain running. A cloud subscription must not be required for console access.
- Live recovery verification: a brief LAN interruption restores the same session and releases/reacquires input safely; a longer interruption stops automatic recovery and offers explicit retry after cleanup. Record the actual controller model and connection mode for each physical input/rumble result. Xbox One and DualShock 4 are both supported targets; untested models remain unverified rather than silently excluded or claimed accepted.
- Keep static/build results separate from live Series X evidence. Do not mark the roadmap item complete from a successful build or synthetic media/controller tests alone.

## Reference

[Xbox Remote Play](https://www.xbox.com/en-ca/consoles/remote-play) identifies Xbox Series X|S and Xbox One with remote features enabled. [Xbox Wire's September 2026 update](https://news.xbox.com/en-us/2026/09/09/xbox-insiders-october-2026-console-features-3/) says Remote Play itself needs no additional subscription.

[OpenXbox's SmartGlass protocol documentation](https://openxbox.org/smartglass-documentation/simple_message/#power-on-request) describes a separate LAN Power On Request (`0xDD02`) and [its client API](https://xbox-smartglass-core-python.readthedocs.io/en/latest/source/xbox.sg.console.html) exposes `power_on`. This is a candidate for the explicit Wake Console action; compatibility with the user's Series X still needs live verification.

XStreaming HEAD `383e19d324f2d3029d1c304752f4d38a9360bb95` was inspected for lifecycle behavior:

- [The normal Disconnect option](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/NativeStream.tsx#L2634-L2645) passes `false` to exit; [exit closes WebRTC and stops the session](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/NativeStream.tsx#L2183-L2207), calling power-off only for the separately selected option. [The session stop](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/xCloud/index.ts#L873-L899) deletes the remote-play session.
- Its optional [Disconnect and power off](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/NativeStream.tsx#L2634-L2645) uses a distinct [Power/TurnOff command](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/web/index.ts#L78-L84). XFrame's normal disconnect follows the no-power-off behavior.
- XStreaming's [standby card](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/components/ConsoleItem.tsx#L122-L146) can combine power-on and start. XFrame deliberately keeps these as separate user actions.

Apple's [Game Controller haptics API](https://developer.apple.com/documentation/gamecontroller/gccontroller/haptics) is optional per controller. Inspect the connected device's supported localities and report unsupported feedback explicitly; an API capability check is an implementation detail, not a reason to restrict the product to one controller model.

The [WebRTC statistics specification](https://www.w3.org/TR/webrtc-stats/) defines the selected candidate pair and its local/remote candidate properties. Implementation must confirm which of those properties the bundled native WebRTC framework exposes and supplement them with live route evidence where necessary.
