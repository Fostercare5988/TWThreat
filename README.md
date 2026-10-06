# TWThreat

Threat bars, target-frame indicators, alerts and a tank-mode view for the enhanced WoW 1.12.1 client. Authors: Xerron/Er and Fostercare5988.

Requires ClassicAPI 1.15.15+ with `C_Timer.NewTicker`, SuperWoW 2.2+, and the supported server threat protocol. The published ClassicAPI floor is a support policy, not an API introduction date. DLL updates require a full game restart.

- `/twt show` opens the main window; `/twt tankmode` enables tank mode.
- The gear icon opens display, scale, font, column and alert settings; the padlock controls movement.
- Tank-mode bars can target the represented creature by GUID.
- Target indicators follow FostercareTweaks' active target frame when available, or Blizzard's target frame.
- Threat queries use one cancellable combat timer. Bar smoothing runs while widths are changing and sleeps when they settle.

Settings remain in `TWT_CONFIG`. No saved settings are reset by this update.

Developer regressions: `python -B -m unittest discover -s tests -q`. These model timer and frame lifecycles; server packets, native rendering and gameplay performance need an in-game check.
