#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2154
# Arch Linux / Arch Linux ARM. The Asahi/Aurora image owns hardware repositories
# and boot packages; this installs the user workstation on that base.
# shellcheck source=common.sh
source "$dotfiles_dir/scripts/linux/common.sh"
# shellcheck source=workstation.sh
source "$dotfiles_dir/scripts/linux/workstation.sh"

arch_required=(base-devel python zsh zsh-autosuggestions zsh-syntax-highlighting
  stow git git-lfs curl wget openssh)
arch_optional=(clang cmake ninja automake pkgconf openssl protobuf zig bats ansible
  pandoc libvips espeak-ng whisper.cpp caddy iperf3 lftp tailscale
  smartmontools dfu-util qemu-system-aarch64 squashfs-tools xorriso android-tools
  ollama podman distrobox)
arch_desktop=(cosmic-session cosmic-terminal cosmic-text-editor cosmic-store
  flatpak networkmanager wl-clipboard noto-fonts-emoji)
arch_desktop_optional=(keepassxc syncthing chromium vlc satty openssh-askpass)

# Pacman has no --skip-unavailable. Resolve optional packages from the synced
# repositories, report omissions, and let dependency/transaction errors fail.
arch_install_optional() {
  local package available selected=()
  available=$(pacman -Slq)
  for package in "$@"; do
    if grep -Fxq "$package" <<<"$available"; then
      selected+=("$package")
    else
      echo "warning: $package is unavailable in the configured Arch ARM repositories" >&2
    fi
  done
  ((${#selected[@]} == 0)) || sudo pacman -S --needed --noconfirm "${selected[@]}"
}

install_system_packages() {
  # Always upgrade the whole system with the initial database refresh.
  sudo pacman -Syu --needed --noconfirm "${arch_required[@]}"
  ensure_mise
  arch_install_optional "${arch_optional[@]}"
  if command -v tailscale >/dev/null 2>&1; then
    sudo systemctl enable --now tailscaled
  fi
  [[ ${SKIP_DESKTOP:-} == 1 ]] && return

  sudo pacman -S --needed --noconfirm "${arch_desktop[@]}"
  if [[ -r /proc/device-tree/compatible ]] && grep -aq 'apple,arm-platform' /proc/device-tree/compatible; then
    sudo pacman -S --needed --noconfirm mesa vulkan-asahi asahi-audio speakersafetyd alsa-ucm-conf-asahi
    sudo systemctl enable --now speakersafetyd
  fi
  arch_install_optional "${arch_desktop_optional[@]}"
  sudo systemctl enable --now NetworkManager
  if ! systemctl is-enabled display-manager.service >/dev/null 2>&1; then
    sudo systemctl enable cosmic-greeter.service
  fi
  sudo systemctl set-default graphical.target
  configure_tailscale_tray
  install_desktop_flatpaks
  bash "$dotfiles_dir/scripts/linux/1password.sh"
  if command -v syncthing >/dev/null 2>&1; then
    systemctl --user enable --now syncthing.service ||
      echo 'warning: enable syncthing.service after logging into COSMIC' >&2
  fi
  echo 'Arch desktop: Chromium installed when available; ChatGPT/Chrome RPMs are Fedora-specific.'
}

install_satty() {
  [[ ${SKIP_DESKTOP:-} == 1 ]] && return
  command -v satty >/dev/null 2>&1 && return
  sudo pacman -S --needed --noconfirm gtk4 libadwaita libepoxy fontconfig
  cargo install --locked satty
}
