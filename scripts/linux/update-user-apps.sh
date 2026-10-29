#!/usr/bin/env bash
set -u
status=0
if command -v flatpak >/dev/null 2>&1; then
  flatpak update --user --noninteractive -y || status=1
fi
if [[ -x $HOME/.local/bin/mise ]]; then
  "$HOME/.local/bin/mise" self-update --yes --no-plugins || status=1
  "$HOME/.local/bin/mise" upgrade --global --no-prune || status=1
fi
if [[ -f $HOME/.local/share/applications/tether.desktop ]]; then
  bash "$(dirname "$0")/tether.sh" || status=1
fi
exit "$status"
