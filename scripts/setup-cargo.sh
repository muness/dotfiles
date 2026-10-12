#!/usr/bin/env bash
set -euo pipefail

dotfiles_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_source="$dotfiles_dir/cargo/.cargo/config.toml"
target_home=${1:-$HOME}

for tool in stow sccache; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required; run this platform's dotfiles installer first." >&2
    exit 2
  fi
done

backup_dir="${XDG_STATE_HOME:-$target_home/.local/state}/dotfiles-backup/$(date -u +%Y%m%dT%H%M%SZ)-$$"
for name in config config.toml; do
  target="$target_home/.cargo/$name"
  [[ -e $target || -L $target ]] || continue
  # Cargo prefers the legacy config file, so back it up even if config.toml is linked.
  if [[ $name == config.toml && $target -ef $config_source ]]; then
    continue
  fi
  mkdir -p "$backup_dir/.cargo"
  mv -- "$target" "$backup_dir/.cargo/$name"
  echo "Backed up $target to $backup_dir/.cargo/$name"
done

# Cargo writes credentials and caches here; never fold the whole directory into the repo.
mkdir -p "$target_home/.cargo"
stow --dir="$dotfiles_dir" --target="$target_home" --no-folding --restow cargo
echo "Linked Cargo configuration from $config_source"
