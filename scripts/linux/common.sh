#!/usr/bin/env bash
# Fallback installers for Linux tools a distro may not package. Sourced.

# Release binaries land here; ~/.local/bin is already on PATH via .zshenv.
linux_bin_dir=$HOME/.local/bin

# Install sccache from its GitHub release when the distro has no package.
ensure_sccache() {
  command -v sccache >/dev/null 2>&1 && return
  local arch tag tmp
  arch=$(uname -m)
  tag=$(curl -fsSL https://api.github.com/repos/mozilla/sccache/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/mozilla/sccache/releases/download/$tag/sccache-$tag-$arch-unknown-linux-musl.tar.gz" |
    tar -xz -C "$tmp" --strip-components=1
  mkdir -p "$linux_bin_dir"
  install -m 0755 "$tmp/sccache" "$linux_bin_dir/sccache"
  rm -rf "$tmp"
  export PATH="$linux_bin_dir:$PATH"
}

ensure_starship() {
  command -v starship >/dev/null 2>&1 && return
  mkdir -p "$linux_bin_dir"
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$linux_bin_dir"
}

ensure_atuin() {
  command -v atuin >/dev/null 2>&1 && return
  curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --no-modify-path
}
