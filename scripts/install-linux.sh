#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Linux installer: Fedora (including Fedora Asahi Remix) or Debian/Ubuntu.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

if [[ $(uname -s) != Linux ]]; then
  echo 'This installer supports Linux.' >&2
  exit 2
fi

# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" fedora "*)
    # shellcheck source=linux/fedora.sh
    source "$dotfiles_dir/scripts/linux/fedora.sh" ;;
  *" debian "*|*" ubuntu "*)
    # shellcheck source=linux/debian.sh
    source "$dotfiles_dir/scripts/linux/debian.sh" ;;
  *)
    echo "Unsupported distribution: ${PRETTY_NAME:-unknown}" >&2
    exit 2 ;;
esac

# Each distro script defines install_system_packages.
install_system_packages

prepare_gitconfig_local /opt/1Password/op-ssh-sign
backup_conflicts "${shared_conflicts[@]}"
stow_packages "${shared_packages[@]}"
install_mise_tools
bash "$dotfiles_dir/scripts/setup-cargo.sh"
install_user_tools
# Distro scripts may define extra steps that need rustup/mise first.
if declare -F install_swamp >/dev/null; then install_swamp; fi
schedule_swamp

zsh -n "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc"
zsh -lic 'command -v mise; printf "zsh configuration: PASS\\n"'

zsh_path=$(command -v zsh)
if [[ $(getent passwd "$USER" | cut -d: -f7) != "$zsh_path" ]]; then
  sudo chsh -s "$zsh_path" "$USER"
fi

echo "Stowed ${shared_packages[*]} from $dotfiles_dir into $HOME"
echo 'Start a new login shell to use zsh by default.'
