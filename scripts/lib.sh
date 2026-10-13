#!/usr/bin/env bash
# Helpers shared by the platform installers. Source this; do not execute it.

dotfiles_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Stow packages that are identical on every platform. setup-cargo.sh handles cargo.
# shellcheck disable=SC2034  # read by the sourcing installers
shared_packages=(zsh vim git mise)

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

# Per-user toolchains that install the same way on macOS and Linux.
install_user_tools() {
  if ! command -v rustup >/dev/null 2>&1 && [[ ! -x $HOME/.cargo/bin/rustup ]]; then
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  fi
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

  if command -v mise >/dev/null 2>&1; then
    echo "Installing mise tools..."
    mise install --yes || echo "warning: some mise tools failed to install" >&2
  fi

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
