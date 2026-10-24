# Omarchy touchpad scrolling

Omarchy's touchpad default on this Asahi installation was `scroll_factor = 0.4`.
Use `1.0` to send 2.5 times as much scrolling movement for the same gesture.
This changes scroll distance; momentum after a flick remains application-specific.

After seeding Omarchy's user configuration, run as the desktop user:

```sh
python3 ~/dotfiles/scripts/linux/omarchy-scroll-speed.py
hyprctl reload
hyprctl getoption input:touchpad:scroll_factor
hyprctl configerrors
```

The helper backs up `~/.config/hypr/input.lua` and appends a managed Lua override,
preserving other settings. Repeated runs update that block without duplicating it.
It also honors `XDG_CONFIG_HOME`. It requires the Lua configuration used by
Hyprland 0.55 and later; it does not convert older `.conf` configurations.

Rerun it after any desktop setup that replaces the input file. To undo it, remove
the block between the `dotfiles touchpad scroll speed` markers and reload Hyprland.

On 2026-10-23, Hyprland 0.56.2 accepted the equivalent live override and reported
`float: 1.000000` with no configuration errors. The previous file was retained.
