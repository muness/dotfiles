# Dotfiles

macOS development environment configuration using [GNU Stow](https://www.gnu.org/software/stow/).

## What's Included

| Tool | Description |
|------|-------------|
| [yabai](https://github.com/koekeishiya/yabai) | Tiling window manager |
| [skhd](https://github.com/koekeishiya/skhd) | Hotkey daemon |
| [borders](https://github.com/FelixKratz/JankyBorders) | Window borders |
| [ghostty](https://ghostty.org/) | Terminal emulator |
| [kitty](https://sw.kovidgoyal.net/kitty/) | Terminal emulator (alt) |
| [zellij](https://zellij.dev/) | Terminal multiplexer |
| [espanso](https://espanso.org/) | Text expander |
| zsh | Shell configuration |
| vim | Editor config |

## Prerequisites

- macOS 13+ (Ventura or later)
- [Homebrew](https://brew.sh/)
- [GNU Stow](https://www.gnu.org/software/stow/) (`brew install stow`)

### Yabai Requirements

Yabai requires [partially disabling SIP](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection) for full functionality.

### Accessibility Permissions

After installation, grant accessibility permissions to:
- yabai
- skhd

Go to **System Settings → Privacy & Security → Accessibility** and add both apps.

## Installation

```bash
# Clone the repository
git clone https://github.com/muness/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Run the install script
./install.sh
```

Or manually:

```bash
# Install dependencies
brew bundle

# Install additional tools not in Brewfile
brew install koekeishiya/formulae/yabai
brew install koekeishiya/formulae/skhd
brew install FelixKratz/formulae/borders

# Stow configs (from dotfiles directory)
stow yabai skhd borders ghostty kitty zellij zsh

# Start services
brew services start yabai
brew services start skhd
```

## Keybindings

All keybindings use `alt` as the modifier.

### Window Navigation

| Key | Action |
|-----|--------|
| `alt + h/j/k/l` | Focus window (west/south/north/east) |
| `alt + shift + h/j/k/l` | Swap window (west/south/north/east) |
| `alt + ctrl + h/j/k/l` | Resize window |
| `alt + f` | Toggle float |
| `alt + m` | Swap with largest window |
| `alt + r` | Rotate layout 90° |

### Spaces

| Key | Action |
|-----|--------|
| `alt + 1/2/3/4` | Focus space 1-4 |
| `alt + shift + 1/2/3/4` | Move window to space 1-4 |
| `alt + d` | Move window to next display |

### Other

| Key | Action |
|-----|--------|
| `alt + o` | Toggle Obsidian |

## Structure

```
dotfiles/
├── yabai/          # Window manager config
├── skhd/           # Hotkey config
├── borders/        # Window borders config
├── ghostty/        # Terminal config (primary)
├── kitty/          # Terminal config (alt)
├── zellij/         # Multiplexer config
├── zsh/            # Shell config (.zshenv, .zprofile, .zshrc)
├── .espanso/       # Text expansion
├── .vimrc          # Vim config
├── Brewfile        # Homebrew dependencies
└── install.sh      # Installation script
```

Each directory is structured for GNU Stow - running `stow <dir>` creates symlinks in `~/.config/` or `~/`.

## Updating

```bash
cd ~/dotfiles
git pull
# Re-stow if new packages added
stow <package>
```

## Uninstalling

```bash
cd ~/dotfiles
stow -D yabai skhd borders ghostty kitty zellij zsh
```
