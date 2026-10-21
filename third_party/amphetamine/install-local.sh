#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/chase.amphetamine"
[[ ! -e "$target" ]] || { echo "Already installed; review local changes before updating: $target" >&2; exit 1; }
mkdir -p "$(dirname "$target")" "$HOME/.local/bin" "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
cp -a "$root" "$target"
ln -s "$target/bin/amphetamine" "$HOME/.local/bin/amphetamine"
cp "$root/packaging/omarchy-amphetamine-cleanup.service" "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-amphetamine-cleanup.service
omarchy-shell shell rescanPlugins
omarchy-shell shell enablePlugin chase.amphetamine '{}'
