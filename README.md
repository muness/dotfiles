# Dotfiles

Cross-platform shell, editor, and terminal-multiplexer configuration plus the
macOS window-management setup. [GNU Stow](https://www.gnu.org/software/stow/)
symlinks selected packages into the home directory.

## What's Included

| Tool | Platform | What it does |
|------|----------|--------------|
| zsh | Linux/macOS | Portable shell startup, history, completion, mise, and optional enhancements |
| [Zellij](https://zellij.dev/) | Linux/macOS | Terminal multiplexer with shared keybindings |
| vim | Linux/macOS | Small editor baseline |
| [yabai](https://github.com/koekeishiya/yabai) | macOS | Tiling window manager |
| [skhd](https://github.com/koekeishiya/skhd) | macOS | Global keyboard shortcuts |
| [borders](https://github.com/FelixKratz/JankyBorders) | macOS | Focused-window borders |
| [Kitty](https://sw.kovidgoyal.net/kitty/) | macOS | Primary terminal and Zellij launcher |
| [Ghostty](https://ghostty.org/) | macOS | Optional terminal configuration |
| [Raycast](https://raycast.com/) | macOS | Centered-master script commands |
| [espanso](https://espanso.org/) | macOS | Text expansion configuration |

## Linux quick start

The Linux installer supports Debian and Ubuntu. It installs only portable CLI
packages, installs Zellij through mise, backs up conflicting files under
`~/.local/state/dotfiles-backup`, stows `zsh`, `zellij`, and `vim`, validates the
configuration, and changes the login shell to zsh.

```bash
git clone https://github.com/muness/dotfiles.git ~/src/dotfiles
cd ~/src/dotfiles
./install-linux.sh
```

It does not stow or install macOS applications, terminal-emulator settings,
secrets, Git identity, or host service configuration.

## macOS quick start

```bash
git clone https://github.com/muness/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

Grant accessibility to **yabai** and **skhd**: **System Settings → Privacy & Security → Accessibility**

Start yabai and skhd with their built-in launchd helpers (these formulas do not use `brew services`). Borders can still use Homebrew services:

```bash
yabai --start-service
skhd --start-service
brew services start borders
```

Open **Kitty** from **Applications** or the Dock (⌘Q any old instance first). The config expects Zellij at **`/opt/homebrew/bin/zellij`** (Apple Silicon Homebrew); on Intel Homebrew, edit `kitty/.config/kitty/zellij.session` to use **`/usr/local/bin/zellij`**.

### Kitty + Zellij

Kitty is wired so GUI launches (Dock/Finder) still see Homebrew on **`PATH`** (`env` + `exe_search_path` in `kitty.conf`). A **`startup_session`** loads **`zellij.session`**, which attaches or creates a session named **`default-session`**. New OS windows (⌘N) use the same POSIX **`zellij-launcher.sh`** helper so **`~/.zshrc`** does not run before Zellij.

**Important:** Kitty **does not** apply `startup_session` when you run something like **`kitty ~/project`** or any invocation that passes a program on the command line. Use **`open -a kitty.app`** or the Dock when you want Zellij on startup.

Saving **`~/.config/zellij/config.kdl`** is often picked up live; if keybindings do not change, quit Zellij once and start again.

In **`kitty.conf`**, several **⌘** shortcuts send the same byte sequences Zellij expects after **⌥t** (tabs) or **⌥⇧p** (panes), so macOS-friendly keys still work inside Kitty.

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

### Centered Master Layout

An opt-in, per-Space layout: one master window centred on screen, other windows
in left and right columns. See
[yabai/.config/yabai/centered-master.md](yabai/.config/yabai/centered-master.md)
for how it works and its current limitations.

| Key | Action |
|-----|--------|
| `⌥ ⇧ c` | Toggle the layout for the current space |
| `⌥ ↩` | Promote the focused window to master |
| `⌥ ⌘ h` / `⌥ ⌘ l` | Narrow / widen the master |
| `⌥ ⌘ 0` | Reset master width to 50% |
| `⌥ ⇧ r` | Repair: rebuild the layout from scratch |

These need skhd running. If it is not (see below), use the Raycast commands
instead.

## Raycast Script Commands

The centered-master actions are also exposed as Raycast script commands, which
is handy if skhd is not running.

`install.sh` stows them to `~/.config/raycast/scripts`. Register the folder once:

**Raycast → Settings → Extensions → Script Commands → Add Script Directory →
`~/.config/raycast/scripts`**

They then appear as *Centered Master: Toggle / Promote / Wider / Narrower /
Reset Width / Repair / Status*. Aliases and per-command hotkeys can be assigned
from the same settings pane.

To add more, drop an executable script in `raycast/.config/raycast/scripts/`
with a Raycast metadata header and re-run `stow -R raycast`:

```bash
#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title My Command
# @raycast.mode compact
# @raycast.packageName Centered Master
```

Note: commands cannot be added to a Raycast *store extension* — those are
compiled bundles. Script commands are the supported way to add your own.

## Structure

```
dotfiles/
├── install-linux.sh
├── yabai/      → ~/.config/yabai/
├── skhd/       → ~/.config/skhd/
├── borders/    → ~/.config/borders/
├── kitty/      → ~/.config/kitty/   (kitty.conf, zellij.session, scripts/zellij-launcher.sh)
├── ghostty/    → optional; `stow ghostty` if you use it
├── zellij/     → ~/.config/zellij/
├── raycast/    → ~/.config/raycast/scripts/
├── zsh/        → ~/.zshenv, ~/.zprofile, ~/.zshrc
├── vim/         → ~/.vimrc
├── .espanso/   → ~/.espanso/
├── Brewfile
└── install.sh
```

## Manual Installation

If you prefer to install selectively:

```bash
brew install stow
brew install koekeishiya/formulae/yabai koekeishiya/formulae/skhd
brew install FelixKratz/formulae/borders
brew install --cask kitty
brew install zellij

# Symlink only what you want
cd ~/dotfiles
stow kitty zellij zsh raycast

# Start tiling stack (same as Quick Start)
yabai --start-service
skhd --start-service
brew services start borders
```

## Updating

```bash
cd ~/src/dotfiles  # Linux; use ~/dotfiles if that is your macOS clone
git pull
stow <package>  # re-stow if configs changed
```

## Uninstalling

```bash
cd ~/dotfiles
stow -D yabai skhd borders kitty zellij zsh raycast
```

Optional: `stow -D ghostty` if you had linked it.
