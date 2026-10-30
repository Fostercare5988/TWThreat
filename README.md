# TWThreat

Threat bars, target-frame indicators, alerts and a tank-mode view for the enhanced WoW 1.12.1 client. Authors: Xerron/Er and Fostercare5988.

Requires ClassicAPI with `C_Timer.NewTicker`, SuperWoW 2.2+, and the supported server threat protocol. DLL updates require a full game restart.

- `/twt show` opens the main window; `/twt tankmode` enables tank mode.
- The gear icon opens display, scale, font, column and alert settings; the padlock controls movement.
- Click a tank-mode bar to target its creature (by GUID, through ClassicAPI); hovering makes it your mouseover.
- Target indicators sit on Blizzard's target frame.
- Threat queries use one cancellable combat timer. Bar smoothing runs while widths are changing and sleeps when they settle.

Settings remain in `TWT_CONFIG`. No saved settings are reset by this update.

Developer regressions: `python -B -m unittest discover -s tests -q`. These model timer and frame lifecycles; server packets, native rendering and gameplay performance need an in-game check.
