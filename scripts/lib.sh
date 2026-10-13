#!/usr/bin/env bash
# Helpers shared by the platform installers. Source this; do not execute it.

dotfiles_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Stow packages that are identical on every platform. setup-cargo.sh handles cargo.
# shellcheck disable=SC2034  # read by the sourcing installers
shared_packages=(zsh vim)

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
stow_packages() {
  local pkg
  for pkg in "$@"; do
    [[ -d $dotfiles_dir/$pkg ]] || { echo "skip: no package $pkg" >&2; continue; }
    echo "  Stowing $pkg..."
    stow --dir="$dotfiles_dir" --target="$HOME" --restow "$pkg"
  done
}
