# Dotfiles

My macOS setup: tiling windows, keyboard-driven workflow, and terminal config. Uses [GNU Stow](https://www.gnu.org/software/stow/) to symlink configs into place.

## What's Included

| Tool | What it does |
|------|--------------|
| [yabai](https://github.com/koekeishiya/yabai) | Automatically arranges windows in a grid (tiling window manager) |
| [skhd](https://github.com/koekeishiya/skhd) | Global keyboard shortcuts |
| [borders](https://github.com/FelixKratz/JankyBorders) | Colored borders around the focused window |
| [ghostty](https://ghostty.org/) | Fast terminal (primary) |
| [kitty](https://sw.kovidgoyal.net/kitty/) | Fast terminal (backup) |
| [zellij](https://zellij.dev/) | Split panes and tabs inside the terminal |
| [espanso](https://espanso.org/) | Type shortcuts that expand into longer text |
| zsh | Shell startup files (.zshenv, .zprofile, .zshrc) |
| vim | Editor config |

## Quick Start

```bash
git clone https://github.com/muness/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

Then grant accessibility permissions to **yabai** and **skhd**:
**System Settings → Privacy & Security → Accessibility**

### Prerequisites

- macOS 13+ (Ventura or later)
- [Homebrew](https://brew.sh/)

### Yabai Requires Partial SIP Disable

For yabai to control windows across all spaces, you need to [partially disable System Integrity Protection](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection). This is safe but requires a reboot.

## Keybindings

All shortcuts use **Option (⌥)** as the modifier.

### Window Navigation (vim-style: h=left, j=down, k=up, l=right)

| Key | Action |
|-----|--------|
| `⌥ h/j/k/l` | Focus window in that direction |
| `⌥ ⇧ h/j/k/l` | Swap window in that direction |
| `⌥ ⌃ h/j/k/l` | Resize window in that direction |
| `⌥ f` | Toggle window between tiled and floating |
| `⌥ m` | Make current window the main (largest) |
| `⌥ r` | Rotate layout 90° |

### Spaces (virtual desktops)

| Key | Action |
|-----|--------|
| `⌥ 1/2/3/4` | Switch to space 1-4 |
| `⌥ ⇧ 1/2/3/4` | Move window to space 1-4 |
| `⌥ d` | Move window to next display |

### Apps

| Key | Action |
|-----|--------|
| `⌥ o` | Open/focus Obsidian |

## Structure

```
dotfiles/
├── yabai/      → ~/.config/yabai/
├── skhd/       → ~/.config/skhd/
├── borders/    → ~/.config/borders/
├── ghostty/    → ~/.config/ghostty/
├── kitty/      → ~/.config/kitty/
├── zellij/     → ~/.config/zellij/
├── zsh/        → ~/.zshenv, ~/.zprofile, ~/.zshrc
├── .espanso/   → ~/.espanso/
├── .vimrc      → ~/.vimrc
├── Brewfile
└── install.sh
```

## Manual Installation

If you prefer to install selectively:

```bash
brew install stow
brew install koekeishiya/formulae/yabai koekeishiya/formulae/skhd
brew install FelixKratz/formulae/borders

# Symlink only what you want
cd ~/dotfiles
stow ghostty zellij zsh

# Start services
brew services start yabai
brew services start skhd
```

## Updating

```bash
cd ~/dotfiles
git pull
stow <package>  # re-stow if configs changed
```

## Uninstalling

```bash
cd ~/dotfiles
stow -D yabai skhd borders ghostty kitty zellij zsh
```
