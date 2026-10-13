#!/usr/bin/env bash
# macOS installer: shared config plus the tiling/terminal stack.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# Packages that only make sense on macOS.
macos_packages=(yabai skhd borders raycast)

if [[ $(uname -s) != Darwin ]]; then
  echo 'This installer supports macOS.' >&2
  exit 2
fi
if ! command -v brew >/dev/null 2>&1; then
  echo 'Homebrew not found. Install it from https://brew.sh' >&2
  exit 1
fi

echo "Installing Brewfile dependencies..."
brew bundle --file="$dotfiles_dir/Brewfile"

backup_conflicts .zshenv .zprofile .zshrc .vimrc "Library/Application Support/Tern/settings.json"
echo "Stowing configuration packages..."
stow_packages "${shared_packages[@]}" "${macos_packages[@]}"
# Tern keeps daemon state next to settings.json, so link only the file, never the directory.
stow --dir="$dotfiles_dir" --target="$HOME" --no-folding --restow tern
bash "$dotfiles_dir/scripts/setup-cargo.sh"

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
MSG
