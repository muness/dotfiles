#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2154
# Workstation helpers shared by Fedora and Arch ARM. Sourced by distro backends.
desktop_flatpaks=(dev.zed.Zed md.obsidian.Obsidian dev.vencord.Vesktop)
caffeine_applet_id=com.github.codevardhan.caffeine-applet

configure_tailscale_tray() {
  command -v tailscale >/dev/null 2>&1 || return 0
  if tailscale configure systray --enable-startup=systemd; then
    systemctl --user daemon-reload
    systemctl --user enable --now tailscale-systray.service ||
      echo 'warning: enable tailscale-systray.service after logging into COSMIC' >&2
  else
    echo 'warning: could not configure the Tailscale tray startup' >&2
  fi
}

install_desktop_flatpaks() {
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y --noninteractive flathub "${desktop_flatpaks[@]}"
  install_caffeine_applet
}

# Install the native COSMIC applet and add it to the panel's right wing.
install_caffeine_applet() {
  flatpak remote-add --user --if-not-exists cosmic https://apt.pop-os.org/cosmic/cosmic.flatpakrepo
  flatpak install --user -y --noninteractive cosmic "$caffeine_applet_id"

  local panel_config="$HOME/.config/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings"
  local default_panel_config=/usr/share/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings
  mkdir -p "$(dirname "$panel_config")"
  if [[ ! -f $panel_config ]]; then
    if [[ ! -f $default_panel_config ]]; then
      echo "warning: COSMIC panel defaults not found; add Caffeine in COSMIC Settings" >&2
      return
    fi
    cp "$default_panel_config" "$panel_config"
  fi

  python3 - "$panel_config" "$caffeine_applet_id" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
applet_id = sys.argv[2]
config = path.read_text()
if applet_id not in config:
    config, count = re.subn(
        r'("com\.system76\.CosmicAppletStatusArea")',
        rf'\1, "{applet_id}"',
        config,
        count=1,
    )
    if count != 1:
        raise SystemExit("Could not find COSMIC Status Area in panel config")
    path.write_text(config)
PY
  echo "Caffeine added to the COSMIC panel; log out and back in to refresh the panel."
}

# swamp ships no aarch64 Linux release; build it once rustup exists.
install_swamp() {
  command -v swamp >/dev/null 2>&1 && return
  cargo install --locked --git https://github.com/open-horizon-labs/swamp swamp
}

