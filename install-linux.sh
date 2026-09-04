#!/usr/bin/env bash
set -euo pipefail

dotfiles_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
packages=(zsh zellij vim)
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
  echo 'mise is required to install Zellij on this host.' >&2
  exit 2
fi
if ! command -v zellij >/dev/null 2>&1; then
  mise use --global zellij@latest
fi

backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backup"
backup_dir="$backup_root/$(date -u +%Y%m%dT%H%M%SZ)"
conflicts=(.zshenv .zprofile .zshrc .vimrc .config/zellij)
for relative in "${conflicts[@]}"; do
  target="$HOME/$relative"
  [[ -e $target || -L $target ]] || continue
  case $(readlink -f -- "$target" 2>/dev/null || true) in
    "$dotfiles_dir"/*) continue ;;
  esac
  mkdir -p "$backup_dir/$(dirname -- "$relative")"
  mv -- "$target" "$backup_dir/$relative"
  echo "Backed up $target to $backup_dir/$relative"
done

cd "$dotfiles_dir"
stow --target="$HOME" --restow "${packages[@]}"

zsh -n "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc"
zsh -lic 'command -v mise; command -v zellij; printf "zsh configuration: PASS\\n"'
zellij setup --check

zsh_path=$(command -v zsh)
if [[ $(getent passwd "$USER" | cut -d: -f7) != "$zsh_path" ]]; then
  sudo chsh -s "$zsh_path" "$USER"
fi

echo "Stowed ${packages[*]} from $dotfiles_dir into $HOME"
echo 'Start a new login shell to use zsh by default.'
