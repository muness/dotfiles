#!/usr/bin/env bash
set -u
status=0
# Root-owned vendor packages need interactive polkit authentication to install.
# Discover updates on the weekly run and surface them instead of skipping them.
if command -v pacman >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
  vendor_updates=$(bash "$(dirname "$0")/vendor-apps.sh" --check) || status=1
  printf '%s\n' "$vendor_updates"
  if [[ $vendor_updates == *'would update'* || $vendor_updates == *'would install'* ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name='Desktop updates' 'Vendor application updates available' \
      "$vendor_updates
Run ~/dotfiles/scripts/linux/vendor-apps.sh to install with graphical authentication."
  fi
fi
if command -v flatpak >/dev/null 2>&1; then
  flatpak update --user --noninteractive -y || status=1
fi
if [[ -x $HOME/.local/bin/mise ]]; then
  "$HOME/.local/bin/mise" self-update --yes --no-plugins || status=1
  "$HOME/.local/bin/mise" upgrade --global --no-prune || status=1
fi
bash "$(dirname "$0")/vendor-apps.sh" --user-only || status=1
exit "$status"
