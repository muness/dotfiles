#!/usr/bin/env bash
# Helpers shared by the platform installers. Source this; do not execute it.

dotfiles_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Stow packages that are identical on every platform. setup-cargo.sh handles cargo.
# shellcheck disable=SC2034  # read by the sourcing installers
shared_packages=(zsh vim git mise shots)

# Files the shared packages would collide with on a fresh or pre-existing home.
# shellcheck disable=SC2034
shared_conflicts=(.zshenv .zprofile .zshrc .vimrc .gitconfig .config/git/ignore .config/mise/config.toml)

# uv-managed CLI tools wanted on every machine.
uv_tools=(markitdown trafilatura batrachian-toad)

# Move aside any existing file that is not already managed by this repo, so stow
# never fails on a conflict and nothing is lost.
backup_conflicts() {
  local backup_root=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backup
  local backup_dir relative target
  backup_dir=$backup_root/$(date -u +%Y%m%dT%H%M%SZ)
  for relative in "$@"; do
    target=$HOME/$relative
    [[ -e $target || -L $target ]] || continue
    case $(realpath "$target" 2>/dev/null || true) in
      "$dotfiles_dir"/*) continue ;;
    esac
    mkdir -p "$backup_dir/$(dirname -- "$relative")"
    mv -- "$target" "$backup_dir/$relative"
    echo "Backed up $target to $backup_dir/$relative"
  done
}

# stow_packages <package>...  (skips packages whose directory does not exist)
# --no-folding links files, never whole directories, so files an app writes
# next to its config (state, caches, credentials) stay out of the repo.
stow_packages() {
  local pkg
  for pkg in "$@"; do
    [[ -d $dotfiles_dir/$pkg ]] || { echo "skip: no package $pkg" >&2; continue; }
    echo "  Stowing $pkg..."
    stow --dir="$dotfiles_dir" --target="$HOME" --no-folding --restow "$pkg"
  done
}

# prepare_gitconfig_local <op-ssh-sign path>
# Run before backup_conflicts: carries machine-specific keys out of an unmanaged
# ~/.gitconfig into ~/.gitconfig.local, then points SSH signing at 1Password.
prepare_gitconfig_local() {
  local signer=$1 local_file=$HOME/.gitconfig.local value
  if [[ -f $HOME/.gitconfig && ! -L $HOME/.gitconfig ]]; then
    value=$(git config --file "$HOME/.gitconfig" --get coderabbit.machineid || true)
    [[ -n $value ]] && git config --file "$local_file" coderabbit.machineid "$value"
  fi
  git config --file "$local_file" gpg.ssh.program "$signer"
  # Hosts without the 1Password app (servers) cannot sign; say so instead of
  # failing every commit. Re-running after installing 1Password undoes this.
  if [[ -x $signer ]]; then
    git config --file "$local_file" --unset commit.gpgsign || true
  else
    git config --file "$local_file" commit.gpgsign false
    echo "warning: $signer not found; commit signing disabled in $local_file" >&2
  fi
}

# Install everything in the global mise config (CLI set and language runtimes)
# and put it on PATH for the rest of the installer. Needs mise and a stowed
# mise package; setup-cargo.sh and install_user_tools depend on the result.
install_mise_tools() {
  command -v mise >/dev/null 2>&1 || { echo 'mise is required' >&2; exit 2; }
  echo "Installing mise tools..."
  # Optional tools may lack a build for this platform; warn and carry on.
  mise install --yes || echo "warning: some mise tools failed to install" >&2
  eval "$(mise env -s bash)"
  # setup-cargo.sh needs sccache; stop here with the real cause, not later.
  command -v sccache >/dev/null 2>&1 ||
    { echo "mise did not install sccache, which setup-cargo.sh needs; see the mise output above" >&2; exit 1; }
}

# Per-user toolchains that install the same way on macOS and Linux.
install_user_tools() {
  if ! command -v rustup >/dev/null 2>&1 && [[ ! -x $HOME/.cargo/bin/rustup ]]; then
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  fi
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

  if ! command -v claude >/dev/null 2>&1; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
  fi

  if command -v uv >/dev/null 2>&1; then
    local tool
    for tool in "${uv_tools[@]}"; do
      uv tool list 2>/dev/null | grep -q "^$tool " || uv tool install "$tool" || true
    done
  fi

  if ! command -v codex >/dev/null 2>&1 && command -v mise >/dev/null 2>&1; then
    mise exec node -- npm install -g @openai/codex || true
  fi
}

# swamp's scheduled observation is the source for every disk-cleanup decision.
# On Linux the collector keeps a change list so each run walks only what moved.
schedule_swamp() {
  command -v swamp >/dev/null 2>&1 || { echo "warning: swamp not installed; skipping its schedule" >&2; return; }
  if [[ $(uname -s) == Linux ]]; then
    swamp schedule --every 15m --collector
  else
    swamp schedule --every 15m
  fi
}

# Enable the stowed systemd user units. Each unit has a ConditionPathExists on
# its config, so enabling is harmless until that config is created. On a
# headless host, lingering keeps them running without a login session.
enable_user_services() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user daemon-reload || { echo "warning: no systemd user session; skipping services" >&2; return 0; }
  local unit
  for unit in "$@"; do
    systemctl --user enable --now "$unit" || echo "warning: could not enable $unit" >&2
  done
  if [[ ${SKIP_DESKTOP:-} == 1 ]]; then
    sudo loginctl enable-linger "$USER" || true
  fi
}

# Ask for the sudo password once and keep the timestamp fresh until the script
# exits, so long installs (Homebrew, casks, dnf) don't prompt over and over.
# The loop shares this terminal's sudo ticket and stops when the script ends.
keep_sudo_alive() {
  sudo -v || return 1
  (
    while sudo -n true 2>/dev/null; do
      sleep "${SUDO_KEEPALIVE_INTERVAL:-50}"
      kill -0 "$$" 2>/dev/null || exit 0
    done
  ) &
  sudo_keepalive_pid=$!
  # shellcheck disable=SC2064  # expand the pid now, not when the trap fires
  trap "kill $sudo_keepalive_pid 2>/dev/null || true" EXIT
}

# Homebrew 7 will not load formulae from third-party taps until you trust them.
# Trust exactly the tap formulae this Brewfile lists, nothing broader. Taps are
# added first because trusting needs the tap to exist.
trust_brewfile_formulae() {
  local brewfile=$1 tap formula
  for tap in $(brew bundle list --tap --file="$brewfile"); do
    brew tap "$tap" || echo "warning: could not tap $tap" >&2
  done
  for formula in $(brew bundle list --formula --file="$brewfile" | grep / || true); do
    brew trust --formula "$formula" || echo "warning: could not trust $formula" >&2
  done
}
