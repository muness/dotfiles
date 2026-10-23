# Omarchy battery charge menu

For the Apple Silicon Arch laptop running Omarchy 4's Quickshell bar and TLP.

```sh
python3 scripts/linux/battery-charge/install.py
```

The installer prompts graphically through polkit to install a root-owned,
fixed-purpose helper. It backs up the current user files under
`~/.local/state/dotfiles/battery-charge/`, extends the user menu and adds a
battery-care glyph beside the indicator group near the clock. It preserves
other widgets, menu entries and shell settings; rerunning updates the same control.
No Omarchy package files are patched. After updating the QML on a running desktop,
use `omarchy-restart-shell` to clear its component cache.

In Home mode the battery-heart glyph is collapsed. Hover the bar's empty center
or indicator group to reveal it alongside the other inactive indicators. In Travel
mode it stays visible as a reminder. Left-click the glyph to toggle directly
between **Home — 80%** and **Travel — 100%**, without opening a menu. The tooltip
reports the current cap and the next click's action. While authentication or the
change is pending, further clicks are disabled. The system polkit authentication
prompt can still appear; cancelling leaves the current cap unchanged. Set `"alwaysShow": true` on its layout entry to keep it visible.
The glyph refreshes immediately after the change, and polls every five seconds
for changes made elsewhere. Explicit Home/Travel choices remain searchable in
the Omarchy menu under **Battery charge limit**, with the active limit checked.

The helper updates `/etc/tlp.d/10-macbook-charge-limit.conf`, applies TLP and
checks the hardware threshold. Both choices persist across restarts. On an apply
failure it restores the previous configuration and attempts to restore the previous
runtime threshold. No reboot, service restart or forced discharge is needed.
Above 80%, the Home setting stops further charging; ordinary use lowers the charge.

This deliberately keeps the standard battery widget: Omarchy reserves its clicks
for its power panel and battery-percentage toggle. The glyph inherits the
bar's fonts, colors and interaction styles.

To remove it, delete the `muness.battery-charge` entry from the shell's bar layout
and the marked battery block from the menu extension. Remove
`~/.config/omarchy/bar/modules/muness.battery-charge.qml` and
`~/.local/bin/battery-charge`, and use polkit to remove
`/usr/local/libexec/dotfiles-set-charge-limit`. The last selected TLP cap remains.

Verification: `python3 -m unittest discover -s scripts/linux/battery-charge -p 'test_*.py'`.
