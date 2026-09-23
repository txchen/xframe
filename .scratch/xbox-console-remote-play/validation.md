# Xbox console remote play validation

Status: implementation candidate ready for physical Series X validation. The roadmap item remains open.

## Static and automated evidence — 2026-09-22

- `swift test --build-system native -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`: 154 tests passed. This includes separate xHome/cloud authorization, home console list/wake/create/delete HTTP behavior, account device fallback when the xHome list fails, SmartGlass certificate Live ID parsing, account-only console listing without xHome authorization, LAN host-candidate/subnet rejection, and bounded rumble packet decoding.
- `bash scripts/build-app.sh`: release app built at `.build/XFrame.app` and signed. `codesign --verify --deep --strict .build/XFrame.app` passed. The packaged `Info.plist` contains `NSLocalNetworkUsageDescription`.
- `git diff --check`: passed.
- The home provider has no `Power/TurnOff` command. Wake uses a separate `Power/WakeUp` request. Disconnect closes local media/input and deletes the home session using the shared owner; cleanup failure retains ownership for retry.
- On a home stream, the selected WebRTC ICE pair must have host candidates with IPv4 addresses on the same active `en*`/`eth*` subnet. Video presentation, audio output, and input handshake wait for this check. A relayed, nonlocal, or unknown selected path fails closed. The policy intentionally does not accept routed private subnets, IPv6-only paths, or VPN interfaces yet.

The standalone Command Line Tools' default `swiftbuild` engine fails to initialize on this machine; the project's existing native-build workaround was used. The test command adds the installed `Testing.framework` search path.

## Physical validation still required

- On the user's Series X, verify account-associated listing, actual SmartGlass Live ID matching, local network permission, and separate service power state versus LAN presence.
- In standby, click **Wake Console**, wait for local availability, then click **Connect** separately. Verify neither wake nor connect launches or changes a game.
- Confirm the selected media route remains local, received stream resolution and frame rate reach the 1080p/up-to-60 target, game audio is audible, and controller input works. Record received FPS separately from game rendering FPS.
- Test physical vibration with the connected Xbox One controller and a DualShock 4 / PS4 controller when available. Record controller connection modes; a parsed packet or available haptic API is not physical rumble evidence.
- Disconnect and verify XFrame's session ends while the Xbox stays powered on and its game remains running. Test a short LAN interruption for same-session recovery and a longer interruption for cleanup followed by manual Connect.

No real Xbox, network path, audio output, or physical controller result has been claimed from the automated checks above.

## Cloud rumble issue reported during physical testing

The user reported that one Palworld vibration caused strong rumble lasting 5–6 seconds in the cloud stream. The prior Core Haptics player scheduled `repeat + 1` full-duration events with intervening delays, and discarded old player references without stopping playback. Both could extend or overlap vibration. XStreaming's ordinary controller path reads these fields but passes only the duration and motor levels to its native vibration call.

The revised player explicitly stops its prior haptic players, plays one replacement pulse per command, bounds each pulse to 0.5 seconds and 60% intensity, and stops engines after the pulse with a short watchdog margin. On a controller exposing only default haptics, trigger-motor percentages are not folded into handle intensity. Packet decoding and the pulse policy have automated regression coverage. Physical strength, timing, and cancellation on Xbox One and DualShock 4 controllers need retesting with the rebuilt app; the user's report describes the prior build.

After this change, the full suite passed 156 tests, the release binary compiled, and a separately staged `.build/XFrame-next.app` passed strict deep signature verification. The running `.build/XFrame.app` was left untouched during the user's cloud stream.
