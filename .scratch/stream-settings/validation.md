# HQ and game-language validation — 2026-09-22

## Automated and build checks

- `bash scripts/test.sh`: 85 tests passed (`.build/stream-preferences-tests.log`).
- Added tests for independent fallback of invalid persisted preferences, persistence, launch-time snapshot isolation, next-session application and outbound HTTP payload/device-header consistency for Standard/English and HQ/zh-CN/zh-TW.
- Existing default session creation, catalog authorization, cleanup and media tests pass.
- `bash scripts/build-app.sh`: release build, local development signing and strict signature verification passed (`.build/stream-preferences-build.log`).
- `git diff --check` passed.

## Signed application UI

- Library sidebar exposes Streaming Settings; default is Standard / English.
- Selected HQ (experimental) and 简体中文 through native pickers; next-session summary updated.
- Quit and relaunched the signed app; both preferences survived and the library remained in English.
- New session summary and settings sheet show the launch snapshot. In-session sheet explains that later changes require End Session and a new launch.
- Corrected descriptive text truncation when the current-session row appears. Final screenshot confirmed fully wrapped descriptions and visible current/next-session instructions.

## Palworld live result

Started fresh sessions after the previous session had ended. Simplified Chinese was visibly applied: the title became 幻兽帕鲁 and menu items included 开始游戏, 加入多人游戏, 求生指南 and 选项. This proves zh-CN works for the tested title; other languages/titles were not physically verified.

HQ was sent using the pinned XStreaming client profile: tizen in both body and device header, 4096x2160 advertised dimensions, Microsoft/unknown device, reference OS version and Edge browser fields. The final signed build successfully connected and played native H.264 with hardware decoding, game audio and active Xbox controller input. Received video remained 1920x1080 at approximately 14.4 Mbps in the main menu. An earlier partial-profile attempt also measured approximately 14.5 Mbps. Previous Standard observations were approximately 14–15 Mbps, so there is **no demonstrated quality/bitrate increase** in this test. Requested capabilities are not received dimensions, and a successful session is not proof HQ was honored. Region/account/title constraints and negotiation remain possible causes, not established explanations. See issues/02-hq-negotiation-validation.md.

The final app is left running at the Chinese Palworld main menu with HQ / 简体中文 saved, controller enabled and Detailed HUD visible. No save was loaded by the agent. Numeric custom bitrate overrides and the separately tracked STREAM/OUT discrepancy were not changed.
