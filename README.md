# Steam Launch Options (Omarchy plugin)

Bar widget + panel to manage Steam `LaunchOptions` stored in `localconfig.vdf`.

## Features

1. **Default launch options** — persistent text field (`~/.config/omarchy/steam-launch-options/defaults.txt`).  
   **Apply to empty** writes those defaults only for installed games whose `LaunchOptions` is missing or blank (covers newly installed games after you apply). Does not overwrite existing options.

2. **Game picker** — search + scrollable list. Names from `appmanifest_*.acf`; icons from local library cache or Steam CDN header art.

3. **Save** — writes per-game options into the active user's `userdata/<id>/config/localconfig.vdf`.

Backend: `scripts/steam_lo.py` (stdlib Python). Backups of `localconfig.vdf` land in `~/.config/omarchy/steam-launch-options/backups/`.

## Install

```sh
# Copy or clone into plugins
mkdir -p ~/.config/omarchy/plugins
cp -a /path/to/steam-launch-options ~/.config/omarchy/plugins/da1nonlycheezit.steam-launch-options

# Or from git after you publish:
# omarchy plugin add https://github.com/da1nonlycheezit/steam-launch-options.git --enable

omarchy plugin validate ~/.config/omarchy/plugins/da1nonlycheezit.steam-launch-options
omarchy plugin enable da1nonlycheezit.steam-launch-options
omarchy bar move da1nonlycheezit.steam-launch-options --section right
# restart shell if needed
omarchy-restart-shell
```

## Steam paths

Resolved in order:

- `~/.steam/steam`
- `~/.local/share/Steam`
- Flatpak: `~/.var/app/com.valvesoftware.Steam/.local/share/Steam`

Libraries from `config/libraryfolders.vdf` (or legacy path).

## CLI helper

```sh
python3 scripts/steam_lo.py list
python3 scripts/steam_lo.py defaults-set 'gamescope -f -- %command%'
python3 scripts/steam_lo.py apply-defaults
python3 scripts/steam_lo.py set 730 'mangohud %command%'
python3 scripts/steam_lo.py get 730
```

## Notes / limits

- Steam should ideally be **closed** when writing `localconfig.vdf`; Steam may rewrite the file on exit if left open.
- True automatic apply on download is not wired (would need inotify on `appmanifest_*.acf` or a service). Use **Apply to empty** after installs.
- VDF edit is regex-based, not a full KeyValues parser; backups are taken before each write.
- Non-game entries (Steamworks, Proton, Redistributables) are filtered from the list.

## License

MIT
