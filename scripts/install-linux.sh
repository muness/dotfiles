#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Linux installer: Fedora, Arch Linux ARM (including Aurora), or Debian/Ubuntu.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

if [[ $(uname -s) != Linux ]]; then
  echo 'This installer supports Linux.' >&2
  exit 2
fi

aurora_mode=
while (($#)); do
  case $1 in
    --aurora) aurora_mode=read-only ;;
    --aurora-enable-touchid) aurora_mode=enabled ;;
    --help|-h)
      echo 'Usage: install.sh [--profile asahi|server] [--aurora|--aurora-enable-touchid]'
      echo 'Aurora options apply to Arch ARM on Apple Silicon and change its kernel/boot bundle.'
      exit 0 ;;
    *) echo "Unknown Linux installer option: $1" >&2; exit 2 ;;
  esac
  shift
done

if ((EUID == 0)); then
  echo 'Run from your own user account with sudo configured, not as root.' >&2
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
  *" arch "*|*" archarm "*|*" alarm "*)
    # shellcheck source=linux/arch.sh
    source "$dotfiles_dir/scripts/linux/arch.sh" ;;
  *)
    echo "Unsupported distribution: ${PRETTY_NAME:-unknown}" >&2
    exit 2 ;;
esac

if [[ -n $aurora_mode ]]; then
  [[ ${ID:-} == arch || ${ID:-} == archarm || ${ID:-} == alarm || " ${ID_LIKE:-} " == *" arch "* ]] ||
    { echo 'Aurora installation requires Arch Linux ARM.' >&2; exit 2; }
  bash "$dotfiles_dir/scripts/linux/aurora.sh" --check
fi
keep_sudo_alive

# Each distro script defines install_system_packages.
install_system_packages
if [[ -n $aurora_mode ]]; then
  if [[ $aurora_mode == enabled ]]; then
    bash "$dotfiles_dir/scripts/linux/aurora.sh" --enable-touchid
  else
    bash "$dotfiles_dir/scripts/linux/aurora.sh" --read-only
  fi
fi

prepare_gitconfig_local /opt/1Password/op-ssh-sign
backup_conflicts "${shared_conflicts[@]}" .config/tern/settings.json
stow_packages "${shared_packages[@]}" systemd tern-linux
install_mise_tools
bash "$dotfiles_dir/scripts/setup-cargo.sh"
install_user_tools
if declare -F install_caffeine_applet >/dev/null; then install_caffeine_applet; fi
# Distro scripts may define extra steps that need rustup/mise first.
if declare -F install_swamp >/dev/null; then install_swamp; fi
if declare -F install_satty >/dev/null; then install_satty; fi
schedule_swamp
enable_user_services caddy.service cloudflared.service

zsh -n "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc"
zsh -lic 'command -v mise; printf "zsh configuration: PASS\\n"'

zsh_path=$(command -v zsh)
if [[ $(getent passwd "$USER" | cut -d: -f7) != "$zsh_path" ]]; then
  sudo chsh -s "$zsh_path" "$USER"
fi

echo "Stowed ${shared_packages[*]} from $dotfiles_dir into $HOME"
echo 'Start a new login shell to use zsh by default.'
