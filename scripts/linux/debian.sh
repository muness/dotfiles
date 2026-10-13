#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2154  # dotfiles_dir comes from lib.sh
# Debian/Ubuntu: zsh, stow and git; mise supplies the rest of the CLI set. Sourced by install-linux.sh.
# shellcheck source=common.sh
source "$dotfiles_dir/scripts/linux/common.sh"

apt_packages=(stow zsh zsh-autosuggestions zsh-syntax-highlighting git git-lfs curl)

install_system_packages() {
  local missing=() package
  for package in "${apt_packages[@]}"; do
    dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -q '^installed$' || missing+=("$package")
  done
  if ((${#missing[@]})); then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
  fi
  ensure_mise
}
