#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2154
# Workstation helpers shared by Fedora and Arch ARM. Sourced by distro backends.
desktop_flatpaks=(md.obsidian.Obsidian dev.vencord.Vesktop)

configure_tailscale_tray() {
  command -v tailscale >/dev/null 2>&1 || return 0
  if tailscale configure systray --enable-startup=systemd; then
    # Tailscale can generate the unit with executable permissions.
    chmod a-x "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/tailscale-systray.service"
    systemctl --user daemon-reload
    systemctl --user enable --now tailscale-systray.service ||
      echo 'warning: enable tailscale-systray.service after logging into the desktop' >&2
  else
    echo 'warning: could not configure the Tailscale tray startup' >&2
  fi
}

install_desktop_flatpaks() {
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y --noninteractive flathub "${desktop_flatpaks[@]}"
}

# swamp ships no aarch64 Linux release; build it once rustup exists.
install_swamp() {
  command -v swamp >/dev/null 2>&1 && return
  cargo install --locked --git https://github.com/open-horizon-labs/swamp swamp
}

