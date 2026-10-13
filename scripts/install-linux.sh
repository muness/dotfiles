#!/usr/bin/env bash
# Debian/Ubuntu installer: portable CLI config only.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

apt_packages=(stow zsh zsh-autosuggestions zsh-syntax-highlighting fzf zoxide fd-find bat ripgrep)

if [[ $(uname -s) != Linux ]] || ! command -v apt-get >/dev/null 2>&1; then
  echo 'This installer supports Debian/Ubuntu Linux hosts.' >&2
  exit 2
fi

missing=()
for package in "${apt_packages[@]}"; do
  dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -q '^installed$' || missing+=("$package")
done
if ((${#missing[@]})); then
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends "${missing[@]}"
fi

if ! command -v mise >/dev/null 2>&1; then
  echo 'mise is required to install sccache on this host.' >&2
  exit 2
fi
command -v sccache >/dev/null 2>&1 || mise use --global sccache@latest

backup_conflicts .zshenv .zprofile .zshrc .vimrc
stow_packages "${shared_packages[@]}"
bash "$dotfiles_dir/scripts/setup-cargo.sh"

zsh -n "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc"
zsh -lic 'command -v mise; printf "zsh configuration: PASS\\n"'

zsh_path=$(command -v zsh)
if [[ $(getent passwd "$USER" | cut -d: -f7) != "$zsh_path" ]]; then
  sudo chsh -s "$zsh_path" "$USER"
fi

echo "Stowed ${shared_packages[*]} from $dotfiles_dir into $HOME"
echo 'Start a new login shell to use zsh by default.'
