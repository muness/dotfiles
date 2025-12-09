# Dotfiles

macOS development environment configuration using [GNU Stow](https://www.gnu.org/software/stow/).

## What's Included

| Tool | Description |
|------|-------------|
| [yabai](https://github.com/koekeishiya/yabai) | Tiling window manager |
| [skhd](https://github.com/koekeishiya/skhd) | Hotkey daemon |
| [sketchybar](https://github.com/FelixKratz/SketchyBar) | Custom status bar |
| [borders](https://github.com/FelixKratz/JankyBorders) | Window borders |
| [kitty](https://sw.kovidgoyal.net/kitty/) | Terminal emulator |
| [zellij](https://zellij.dev/) | Terminal multiplexer |
| [espanso](https://espanso.org/) | Text expander |
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

### Hide the macOS Menu Bar

To use sketchybar as your status bar, hide the default menu bar:

**System Settings → Control Center → Automatically hide and show the menu bar → Always**

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
brew install FelixKratz/formulae/sketchybar
brew install FelixKratz/formulae/borders

# Stow configs (from dotfiles directory)
stow yabai skhd sketchybar borders kitty zellij

# Start services
brew services start yabai
brew services start skhd
brew services start sketchybar
```

## Keybindings

All keybindings use `alt` as the modifier.

### Window Navigation

| Key | Action |
|-----|--------|
| `alt + h/j/k/l` | Focus window (west/south/north/east) |
| `alt + shift + h/j/k/l` | Swap window (west/south/north/east) |
| `alt + ctrl + h/j/k/l` | Resize window |
| `alt + return` | Toggle fullscreen |
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
| `alt + b` | Toggle sketchybar visibility |
| `alt + o` | Toggle Obsidian |

## Structure

```
dotfiles/
├── yabai/          # Window manager config
├── skhd/           # Hotkey config
├── sketchybar/     # Status bar config
├── borders/        # Window borders config
├── kitty/          # Terminal config
├── zellij/         # Multiplexer config
├── .espanso/       # Text expansion
├── .vimrc          # Vim config
├── Brewfile        # Homebrew dependencies
└── install.sh      # Installation script
```

Each directory is structured for GNU Stow - running `stow <dir>` creates symlinks in `~/.config/`.

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
stow -D yabai skhd sketchybar borders kitty zellij
```
