# Dotfiles

Cross-platform shell and editor configuration plus the
macOS window-management setup. [GNU Stow](https://www.gnu.org/software/stow/)
symlinks selected packages into the home directory.

## What's Included

| Tool | Platform | What it does |
|------|----------|--------------|
| zsh | Linux/macOS | Portable shell startup, history, completion, mise, and optional enhancements |
| vim | Linux/macOS | Small editor baseline |
| git | Linux/macOS | Identity, 1Password SSH signing, gh credentials; per-machine bits in `~/.gitconfig.local` |
| mise | Linux/macOS | Global language toolchains (`~/.config/mise/config.toml`) |
| Cargo + sccache | Linux/macOS | Smaller dev/test debug output, a shared compiler cache, and a per-checkout `CARGO_TARGET_DIR` outside the source tree |
| COSMIC + Fedora apps | Fedora Asahi | Desktop, Chromium, 1Password, flatpaks (see `scripts/linux/fedora.sh`) |
| Shared `/Volumes/src` | dual boot | ext4 partition both OSes mount; see [docs/asahi-dual-boot.md](docs/asahi-dual-boot.md) |
| [yabai](https://github.com/koekeishiya/yabai) | macOS | Tiling window manager |
| [skhd](https://github.com/koekeishiya/skhd) | macOS | Global keyboard shortcuts |
| [borders](https://github.com/FelixKratz/JankyBorders) | macOS | Focused-window borders |
| Tern | macOS | Terminal settings (`settings.json` only; daemon state is not linked) |
| [Raycast](https://raycast.com/) | macOS | Centered-master script commands |
| [espanso](https://espanso.org/) | macOS | Text expansion configuration |

## Layout of the installers

`./install.sh` detects the OS and runs one of two scripts. Both source
`scripts/lib.sh` for shared helpers and the shared package list
(`zsh vim git mise`), then run `scripts/setup-cargo.sh` and install rustup,
mise tools, Claude Code and a few uv tools. Stow runs with `--no-folding`, so
only files are linked and apps can't write state into the repo.

| Script | Adds on top of the shared setup |
|--------|---------------------------------|
| `scripts/install-macos.sh` | `Brewfile`, yabai/skhd/borders/raycast packages, espanso link, services |
| `scripts/install-linux.sh` | `scripts/linux/fedora.sh` (dnf, COSMIC, flatpaks, 1Password) or `scripts/linux/debian.sh` (apt CLI set), login shell change |

## Linux quick start

**Fedora / Fedora Asahi Remix:** adds the mise, Tailscale and 1Password repos,
installs the CLI set with dnf, then COSMIC, Chromium, KeePassXC, Syncthing, the
1Password app and flatpaks (Zed, Obsidian, Vesktop). Set `SKIP_DESKTOP=1` on a
headless host. Builds swamp from source.

**Debian / Ubuntu:** installs only the portable CLI packages; requires mise.

Both back up conflicting files under `~/.local/state/dotfiles-backup`, stow
the shared packages and Cargo config, validate zsh, and change the login
shell to zsh.

```bash
git clone https://github.com/muness/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

Secrets, `~/.ssh/config` and host services are not managed here.

For the macOS + Fedora Asahi dual boot with a shared source partition, follow
[docs/asahi-dual-boot.md](docs/asahi-dual-boot.md).

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

### Rust builds

`.zshenv` sets `CARGO_TARGET_DIR` to `~/.cache/cargo-target/<git root path>`
on every directory change, so build output never lands in the (possibly
shared) source tree and builds in different checkouts don't wait on each
other's lock. To keep `./target` in one repo, add
`export CARGO_TARGET_DIR=$PWD/target` to its `.envrc`.

Both installers link `cargo/.cargo/config.toml` to `~/.cargo/config.toml` and install sccache (Homebrew on macOS, mise on Linux). Dev and test profiles keep line tables for workspace backtraces and omit dependency debug information. Incremental compilation keeps its default behavior.

The setup backs up an existing config, including Cargo's legacy `~/.cargo/config`, under `${XDG_STATE_HOME:-~/.local/state}/dotfiles-backup`. It links only `config.toml`; credentials, registries, and caches remain in the home directory. To apply just this package when Stow and sccache are already installed:

```bash
bash scripts/setup-cargo.sh
```

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

One master window centred on screen, others in left/right columns. Implemented
as a facade over yabai rather than a BSP layout — see
[yabai/.config/yabai/centered-master.md](yabai/.config/yabai/centered-master.md)
for how it works and what it trades away.

| Key | Action |
|-----|--------|
| `⌥ ↩` | Centre this space, or release it if already centred |
| `⌥ ⇧ ↩` | Promote the focused window to master |
| `⌥ ⌘ h` / `⌥ ⌘ l` | Narrow / widen the master |
| `⌥ ⌘ 0` | Reset master width to 50% |
| `⌥ ⇧ r` | Re-render if something drifted |

A space is centred iff it has a master; there is no enable flag. `yabai -m
space --layout bsp` will not release it -- managed windows are floating and
outside the tree, so `⌥ ↩` is the way back. The `⌥ hjkl`
focus and swap cluster routes through the same script and behaves exactly as
before on spaces that are not centred.

Needs skhd running; if it is not, use the Raycast commands below.

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
├── install.sh            (dispatches to scripts/install-{macos,linux}.sh)
├── cargo/      → ~/.cargo/config.toml
├── scripts/              (lib.sh, install-macos.sh, install-linux.sh, setup-cargo.sh)
│   ├── linux/            (fedora.sh, debian.sh, common.sh, 1password.sh, hqplayer-distrobox.sh)
│   └── dualboot/         (src-partition.sh, src-mount-linux.sh, src-macos.sh, src-doctor.sh)
├── docs/asahi-dual-boot.md
├── git/        → ~/.gitconfig, ~/.config/git/ignore
├── mise/       → ~/.config/mise/config.toml
├── yabai/      → ~/.config/yabai/
├── skhd/       → ~/.config/skhd/
├── borders/    → ~/.config/borders/
├── tern/       → ~/Library/Application Support/Tern/settings.json
├── raycast/    → ~/.config/raycast/scripts/
├── zsh/        → ~/.zshenv, ~/.zprofile, ~/.zshrc
├── vim/         → ~/.vimrc
├── .espanso/   → ~/.espanso/
└── Brewfile              (macOS only)
```

## Manual Installation

If you prefer to install selectively:

```bash
brew install stow
brew install koekeishiya/formulae/yabai koekeishiya/formulae/skhd
brew install FelixKratz/formulae/borders

# Symlink only what you want
cd ~/dotfiles
stow zsh vim raycast

# Start tiling stack (same as Quick Start)
yabai --start-service
skhd --start-service
brew services start borders
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
stow -D yabai skhd borders tern zsh vim git mise raycast
```
