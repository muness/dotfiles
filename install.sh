#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing dotfiles from $DOTFILES_DIR"

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh"
    exit 1
fi

# Install stow if not present
if ! command -v stow &> /dev/null; then
    echo "Installing GNU Stow..."
    brew install stow
fi

# Install Brewfile dependencies
echo "Installing Brewfile dependencies..."
brew bundle --file="$DOTFILES_DIR/Brewfile"

# Install window management tools (not in Brewfile)
echo "Installing yabai, skhd, sketchybar, borders..."
brew install koekeishiya/formulae/yabai 2>/dev/null || true
brew install koekeishiya/formulae/skhd 2>/dev/null || true
brew install FelixKratz/formulae/sketchybar 2>/dev/null || true
brew install FelixKratz/formulae/borders 2>/dev/null || true

# Install Ghostty and Zellij
brew install --cask ghostty 2>/dev/null || true
brew install zellij 2>/dev/null || true

# Stow packages
echo "Stowing configuration packages..."
cd "$DOTFILES_DIR"

PACKAGES=(yabai skhd sketchybar borders ghostty zellij)

for pkg in "${PACKAGES[@]}"; do
    if [ -d "$pkg" ]; then
        echo "  Stowing $pkg..."
        stow -R "$pkg"
    fi
done

# Handle dotfiles in root (espanso, vimrc)
if [ -d ".espanso" ]; then
    echo "  Linking .espanso..."
    ln -sf "$DOTFILES_DIR/.espanso" "$HOME/.espanso"
fi

if [ -f ".vimrc" ]; then
    echo "  Linking .vimrc..."
    ln -sf "$DOTFILES_DIR/.vimrc" "$HOME/.vimrc"
fi

# Start services
echo ""
echo "Starting services..."
brew services start yabai 2>/dev/null || true
brew services start skhd 2>/dev/null || true
brew services start sketchybar 2>/dev/null || true

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Grant accessibility permissions to yabai and skhd:"
echo "     System Settings → Privacy & Security → Accessibility"
echo ""
echo "  2. For full yabai functionality, disable SIP:"
echo "     https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection"
echo ""
echo "  3. Restart your terminal or log out/in for changes to take effect."
