#!/usr/bin/env bash
# Linux bootstrap helpers. Sourced.

# Release binaries land here; ~/.local/bin is already on PATH via .zshenv.
linux_bin_dir=$HOME/.local/bin

# Distros without a mise package (Debian, Ubuntu) get the official installer.
# Everything else in the CLI set comes from mise itself.
ensure_mise() {
  command -v mise >/dev/null 2>&1 && return
  mkdir -p "$linux_bin_dir"
  curl -fsSL https://mise.run | MISE_INSTALL_PATH="$linux_bin_dir/mise" sh
  export PATH="$linux_bin_dir:$PATH"
}
