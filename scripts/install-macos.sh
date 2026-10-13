#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# macOS installer: shared config plus the tiling/terminal stack.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# Packages that only make sense on macOS.
macos_packages=(yabai skhd borders raycast)

if [[ $(uname -s) != Darwin ]]; then
  echo 'This installer supports macOS.' >&2
  exit 2
fi
if ! command -v brew >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/brew ]]; then
  echo "Installing Homebrew (also installs the Xcode Command Line Tools)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

echo "Installing Brewfile dependencies..."
brew bundle --file="$dotfiles_dir/Brewfile"

prepare_gitconfig_local /Applications/1Password.app/Contents/MacOS/op-ssh-sign
backup_conflicts "${shared_conflicts[@]}" "Library/Application Support/Tern/settings.json"
echo "Stowing configuration packages..."
stow_packages "${shared_packages[@]}" "${macos_packages[@]}"
# Tern keeps daemon state next to settings.json; --no-folding keeps it out of the repo.
stow_packages tern
bash "$dotfiles_dir/scripts/setup-cargo.sh"
install_user_tools

# espanso reads ~/.espanso as a whole directory, so it is linked rather than stowed.
ln -sfn "$dotfiles_dir/.espanso" "$HOME/.espanso"

echo "Starting services..."
yabai --start-service || true
skhd --start-service || true
brew services start borders || true

cat <<'MSG'

Installation complete. Next steps:
  1. Grant accessibility to yabai and skhd:
     System Settings → Privacy & Security → Accessibility
  2. For full yabai functionality, partially disable SIP:
     https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
  3. Restart your terminal.
  4. Dual boot with a shared /Volumes/src: see docs/asahi-dual-boot.md.
MSG
