# Add configurable HUD and measured video bitrate

Status: needs-triage
Resolution: implemented; Xbox One HUD cycling accepted by user
Type: task

Implement ../spec.md. Reference ../../stream-settings/xstream-research.md for the upstream data paths. User approved keyboard and controller shortcuts. Quality-profile and startup-language settings remain separately tracked research, not part of this HUD increment.

## Comments

- 2026-09-22: Implementation started. Preserve existing working controller transport and media pipeline.

- 2026-09-22: Implemented; 80 tests, release build and signing pass. Live Palworld video bitrate and keyboard preset cycle verified. Awaiting physical Xbox View+Menu feedback; see ../validation.md.

- 2026-09-22: User reported intermittent chord recognition and a macOS recording confirmation. Captured 128 ms button stagger reproduced the failed toggle. Fixed recognition to 300 ms and scoped Menu/Options system-gesture capture to focused input; 82 tests pass. Awaiting rebuilt app physical validation.

- 2026-09-22: Rebuilt version accepted on Xbox One Bluetooth in Palworld. User: “这次正常了, 每次都能顺利切换”. Repeated View+Menu cycling is confirmed working. The reply describes the overall test as normal but does not separately enumerate standalone-button and recording-dialog results. Implementation and Xbox cycling acceptance are complete; status returns to needs-triage for tracker disposition because the configured vocabulary has no completed status. PS4 and other controller models remain untested.
