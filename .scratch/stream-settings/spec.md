# Cloud streaming preferences

User authorized HQ and game-language implementation on 2026-09-22.

- Provide Streaming Settings in the library with persistent Standard / HQ (experimental) quality and explicit game language choices, including en-US, zh-CN and zh-TW.
- Standard preserves the current macOS / 1920x1080 client profile. HQ requests the reference tizen / 4096x2160 capability profile consistently in session settings and device header, including the reference device make/model, OS version and browser fields. These are requested capabilities, not guaranteed received dimensions or a host GPU selection.
- Keep actual received bitrate/dimensions visible via the existing HUD. HQ still uses automatically negotiated bitrate; a numeric custom bitrate override is outside this increment.
- Snapshot preferences synchronously when Start is invoked. Editing settings during a session affects the next new session only, never the active allocation or an in-progress create request.
- Send language in settings.locale independently of app/catalog language. Preserve English app/catalog UI. Explain title-dependent language support and new-session requirement.
- Keep defaults Standard / English for existing installations. Invalid persisted values fall back independently to defaults.
- Validate persistence, outbound request body/header, default behavior and launch-time snapshot/next-session application. Separately validate the signed UI and actual Palworld language/HQ results.
