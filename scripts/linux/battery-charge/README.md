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

On this TLP-managed host, the stock `asahi-scripts` charge-limit persistence
must stay disabled: its sysfs path watcher repeatedly starts until it hits
systemd's rate limit, and its udev rule can restore an older cap over TLP's
setting. The local `/etc/udev/rules.d/93-macsmc-battery-charge-control.rules`
override points to `/dev/null`, and
`macsmc-battery-charge-control-end-threshold.{path,service}` are masked.
TLP remains responsible for restoring the selected cap at boot and power changes.

This deliberately keeps the standard battery widget: Omarchy reserves its clicks
for its power panel and battery-percentage toggle. The glyph inherits the
bar's fonts, colors and interaction styles.

To remove it, delete the `muness.battery-charge` entry from the shell's bar layout
and the marked battery block from the menu extension. Remove
`~/.config/omarchy/bar/modules/muness.battery-charge.qml` and
`~/.local/bin/battery-charge`, and use polkit to remove
`/usr/local/libexec/dotfiles-set-charge-limit`. The last selected TLP cap remains.

Verification: `python3 -m unittest discover -s scripts/linux/battery-charge -p 'test_*.py'`.

## TLP power-event loop

On this host, frequent macsmc power-supply change events caused TLP's stock
udev rule to repeatedly run `tlp auto`, sustaining a CPU-consuming event storm.
`config/udev/85-tlp.rules` retains TLP's USB and disk rules and invokes
`tlp-power-change.py` only for the AC supply. The helper serializes events and
runs TLP only when the actual AC online state changes. Install the helper as
`/usr/local/libexec/dotfiles-tlp-power-change` (root-owned, mode 755), install
the rule at `/etc/udev/rules.d/85-tlp.rules` (mode 644), and reload udev rules.
This local override should be reviewed when the packaged TLP rule changes.

## Power connection warnings

A user service watches macsmc power events and power readings. It warns when
at least 80 battery/AC events arrive in 30 seconds, or when a USB-C power
source is detected while the battery drains at least 5 W for 60 seconds.
Warnings repeat at most once per ten minutes. These symptoms can have several
causes; the warning cannot identify a bad cable and cannot detect a cable that
is completely invisible to the system. Stop with `systemctl --user disable --now power-warning.service`.
