#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2154  # dotfiles_dir comes from lib.sh
# Debian/Ubuntu: portable CLI packages only. Sourced by install-linux.sh.
# shellcheck source=common.sh
source "$dotfiles_dir/scripts/linux/common.sh"

apt_packages=(stow zsh zsh-autosuggestions zsh-syntax-highlighting fzf zoxide fd-find bat ripgrep git git-lfs curl)

install_system_packages() {
  local missing=() package
  for package in "${apt_packages[@]}"; do
    dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -q '^installed$' || missing+=("$package")
  done
  if ((${#missing[@]})); then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
  fi
  if ! command -v mise >/dev/null 2>&1; then
    echo 'mise is required on this host: https://mise.jdx.dev/getting-started.html' >&2
    exit 2
  fi
  ensure_sccache
}
