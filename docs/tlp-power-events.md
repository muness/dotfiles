# TLP power-event guard

The local udev rule avoids a macsmc power-event feedback loop by applying TLP
only when the AC online state changes. Install `scripts/linux/tlp-power-change.py`
as `/usr/local/libexec/dotfiles-tlp-power-change` (root-owned, mode 755), and
`config/udev/85-tlp.rules` as `/etc/udev/rules.d/85-tlp.rules` (mode 644);
reload udev rules afterward. Review the override when TLP updates its rules.

Power Flow and its connection warning live at https://github.com/muness/omarchy-power-flow.
