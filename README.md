# Dotfiles

Shell, editor, toolchain and desktop configuration for three kinds of machine:
a Mac, an Apple Silicon Linux laptop (Fedora Asahi or Arch ARM/Aurora),
and headless Linux servers such as the homelab. One repo, one command, a
profile per machine. [GNU Stow](https://www.gnu.org/software/stow/) symlinks
config into the home directory, and [mise](https://mise.jdx.dev/) installs the
CLI tools and language runtimes everywhere.

## Quick start

```bash
git clone https://github.com/muness/dotfiles.git ~/dotfiles
~/dotfiles/install.sh        # picks the profile for this machine
```

| Machine | Profile | Picked when | After the install |
|---------|---------|-------------|-------------------|
| Mac | `mac` | Darwin | [Grant yabai/skhd accessibility](#macos-quick-start), then restart the terminal |
| Apple Silicon laptop | `asahi` | Apple device tree, or Asahi/Aurora kernel | Reboot into COSMIC, set up 1Password. [Fedora](docs/asahi-dual-boot.md) / [Arch ARM + Aurora, including triple boot](docs/asahi-arch-aurora.md) |
| Linux server / homelab | `server` | any other Linux | Nothing; no desktop is installed. Start a new login shell |

Force a profile with `./install.sh --profile mac|asahi|server` (or
`DOTFILES_PROFILE=server`). The installer is safe to re-run: existing files are
moved to `~/.local/state/dotfiles-backup/<timestamp>` before linking, and
tools that are already installed are skipped.

Debian and Ubuntu also work as `server` hosts: apt provides zsh, stow and git,
and the installer bootstraps mise for everything else.

Arch Linux ARM uses pacman for system packages and the same COSMIC desktop and
mise tools. On a fresh native Apple Silicon Arch installation,
`./install.sh --profile asahi --aurora` installs the pinned upstream Aurora
kernel/boot stack with SEP writes disabled. `scripts/linux/aurora.sh` also runs
independently. See the [Arch/Aurora runbook](docs/asahi-arch-aurora.md) for boot
isolation, private COSMIC settings transfer, and deliberate Touch ID activation.

On Arch ARM, Chrome and ChatGPT desktop are included. Re-run
`scripts/linux/vendor-apps.sh` to update their native vendor binaries; `--check`
checks versions without installing. The helper verifies vendor SHA256 hashes
and builds local pacman packages, so no AUR helper or Debian/RPM tools are needed.

## What differs by OS

| | macOS (`mac`) | Apple Silicon Linux (`asahi`) | Server (`server`) |
|---|---|---|---|
| System packages | `Brewfile` (formulae and casks) | dnf or pacman; flatpak (Zed, Obsidian, Vesktop, Caffeine Applet); native Chrome/ChatGPT (vendor RPMs on Fedora, locally repackaged vendor binaries on Arch) | dnf, pacman, or apt |
| CLI tools and runtimes | mise | mise | mise |
| Desktop and windows | yabai, skhd, borders, Raycast | COSMIC and its tiling | none |
| Screenshots | built-in tools; `shot-share` for links | `shot-annotate` (cosmic-screenshot into Satty); `shot-share` | none |
| Background services | launchd, not managed here | systemd user units (caddy, cloudflared) and swamp's own | same, plus lingering so they run without a login |
| 1Password SSH agent | app socket | `~/.1password/agent.sock` | no app; commit signing is switched off |
| Source tree | `~/src`, shared `/Volumes/src` when dual booting | same shared partition | wherever you clone |

Everything else is identical on all three: zsh startup, git config, vim,
Cargo and sccache settings, and the mise toolchain list.

## Day to day

**Add a CLI tool or language runtime.** Add one line to
`mise/.config/mise/config.toml` (for example `hyperfine = "latest"`), then run
`mise install`. Every machine gets it the next time it pulls and installs.
The Brewfile and the dnf, pacman and apt lists hold only what mise can't: shells and
zsh plugins, stow, GUI apps, and system or kernel-level packages.

**Python is always mise's.** `python = "3.14"` is pinned in that file, and
mise's shims directory comes first on `PATH` in `.zshenv` and `.zprofile`. So
scripts, IDEs and non-interactive shells get it too, never Homebrew's or the
distro's `/usr/bin/python3`. The system one stays installed because dnf needs
it; you just never reach it by typing `python`. `uv` creates venvs from it.

**Change config.** Edit files in `~/dotfiles`; the home directory holds
symlinks into it. A new file inside an existing package needs `stow -R <package>`
(see [Updating](#updating)).

**Share a screenshot.** `shot-share [file]` uploads an image to the homelab
under a random name and copies the link (works on macOS and Linux). On Linux,
`shot-annotate` captures a region with cosmic-screenshot and opens Satty; bind
it to a key in COSMIC settings. Configure the upload once per machine in
`~/.config/shots/env`, which is not in this repo:

```
SHOT_UPLOAD_TARGET=homelab:/srv/shots
SHOT_BASE_URL=https://shots.example
```

**Run services on Linux.** The installer enables `caddy.service` and
`cloudflared.service` as systemd user units. Each stays idle until its config
exists: `~/.config/caddy/Caddyfile` and `~/.cloudflared/config.yml`. Check them
with `systemctl --user status caddy`. Other Mac launch agents belong to their own
repos; [docs/asahi-dual-boot.md](docs/asahi-dual-boot.md#launch-agents-on-linux) lists them.

**Not managed here:** secrets, `~/.ssh/config`, and per-machine git settings
(those go in `~/.gitconfig.local`).

## How the installers fit together

`./install.sh` runs `scripts/install-macos.sh` for `mac`, or
`scripts/install-linux.sh` for `asahi` and `server` (`server` sets
`SKIP_DESKTOP=1`). Both source `scripts/lib.sh` and follow the same order:

1. System packages: `Brewfile`, or `scripts/linux/fedora.sh` / `debian.sh`.
2. Back up conflicting files, then stow `zsh vim git mise shots` (plus the
   macOS window-management packages, or `systemd` on Linux) with `--no-folding`,
   so only files are linked and apps can't write state into the repo.
3. `mise install` for the CLI set and runtimes, put on `PATH` for the rest of
   the run.
4. `scripts/setup-cargo.sh`, rustup, Claude Code and a few uv tools.
5. Schedule `swamp observe` every 15 minutes, and on Linux enable the systemd
   user units.

On Fedora the system step also adds the mise, Tailscale and 1Password repos and
installs COSMIC, Chromium, KeePassXC, Syncthing, VLC, the 1Password app, the
ChatGPT desktop app and the flatpaks. swamp and Satty are built from source
because neither ships an aarch64 Linux release.

The Fedora desktop setup adds the Caffeine applet to the COSMIC panel and
enables Tailscale's Linux systray in COSMIC's Status Area. Log out and back in
after the first setup to refresh the panel. Then run `sudo tailscale up` once to
connect this machine to the Fleet tailnet.

## macOS quick start

Run `./install.sh` as above. It also links Tern's `settings.json` and the espanso config. Then grant accessibility to **yabai** and **skhd**: **System Settings → Privacy & Security → Accessibility**

Start yabai and skhd with their built-in launchd helpers (these formulas do not use `brew services`). Borders can still use Homebrew services:

```bash
yabai --start-service
skhd --start-service
brew services start borders
```

### Prerequisites

- macOS 13+ (Ventura or later)
- [Homebrew](https://brew.sh/)

### Yabai Requires Partial SIP Disable

For yabai to control windows across all spaces, you need to [partially disable System Integrity Protection](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection). This is safe but requires a reboot.

## Rust builds (both OSes)

`cargo/.cargo/config.toml` sets `build.build-dir` to
`{cargo-cache-home}/build/{workspace-path-hash}`: intermediates go to
`~/.cargo/build/<hash>` on each OS, final binaries stay in `./target`. swamp
links each of those directories back to its project, so cleanup decisions come
from `swamp report --view reclaim` (the installers schedule `swamp observe`
every 15 minutes).

Both installers link `cargo/.cargo/config.toml` to `~/.cargo/config.toml` and install sccache through mise. Dev and test profiles keep line tables for workspace backtraces and omit dependency debug information. Incremental compilation keeps its default behavior.

The setup backs up an existing config, including Cargo's legacy `~/.cargo/config`, under `${XDG_STATE_HOME:-~/.local/state}/dotfiles-backup`. It links only `config.toml`; credentials, registries, and caches remain in the home directory. To apply just this package when Stow and sccache are already installed:

```bash
bash scripts/setup-cargo.sh
```

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
├── install.sh            (picks a profile, runs scripts/install-{macos,linux}.sh)
├── cargo/      → ~/.cargo/config.toml
├── scripts/              (lib.sh, install-macos.sh, install-linux.sh, setup-cargo.sh)
│   ├── linux/            (fedora.sh, debian.sh, common.sh, 1password.sh, hqplayer-distrobox.sh)
│   └── dualboot/         (src-partition.sh, src-mount-linux.sh, src-macos.sh, src-doctor.sh)
├── docs/asahi-dual-boot.md
├── git/        → ~/.gitconfig, ~/.config/git/ignore
├── mise/       → ~/.config/mise/config.toml   (the portable CLI list)
├── shots/      → ~/.local/bin/shot-{annotate,share}
├── systemd/    → ~/.config/systemd/user/      (Linux only)
├── yabai/      → ~/.config/yabai/
├── skhd/       → ~/.config/skhd/
├── borders/    → ~/.config/borders/
├── tern/       → ~/Library/Application Support/Tern/settings.json
├── tern-linux/ → ~/.config/tern/settings.json (same settings on Linux)
├── raycast/    → ~/.config/raycast/scripts/
├── zsh/        → ~/.zshenv, ~/.zprofile, ~/.zshrc
├── vim/         → ~/.vimrc
├── .espanso/   → ~/.espanso/
└── Brewfile              (macOS only)
```

## Manual installation (macOS)

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
./install.sh          # re-runs everything; already-installed tools are skipped
# or, for config-only changes:
stow --no-folding --restow <package>
```

## Uninstalling

```bash
cd ~/dotfiles
# macOS
stow -D yabai skhd borders tern zsh vim git mise shots raycast cargo
# Linux
stow -D zsh vim git mise shots cargo systemd
```

Backups of anything the installer moved aside stay in
`~/.local/state/dotfiles-backup`.
