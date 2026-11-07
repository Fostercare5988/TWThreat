# TWThreat

Threat bars, target-frame indicators, alerts and a tank-mode view for the enhanced WoW 1.12.1 client. Authors: Xerron/Er and Fostercare5988.

Requires ClassicAPI, SuperWoW and the supported server threat protocol. DLL updates require a full game restart.

- `/twt show` (or `/twtshow`) opens the main window; `/twt tankmode` turns the tank window on or off (warriors, paladins, druids).
- The gear icon opens display, scale, font, column and alert settings; the padlock locks the window in place.
- Threat shows for elite and boss targets while you fight them in a group.
- The bars glide between the server's answers instead of jumping: each bar belongs to one player, slides to its new rank, and its numbers roll with it. Threat per second is measured over the last few seconds.
- Click a tank-mode row to target its creature (by GUID, through ClassicAPI); hovering makes it your mouseover.
- Target indicators sit on Blizzard's target frame. In tank mode the full-screen glow and the warning sound stay quiet; their settings are kept.

Settings remain in `TWT_CONFIG`. 1.5.0 clears two retired settings (`skeram`, `debug`) and keeps the rest.
