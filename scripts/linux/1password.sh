#!/usr/bin/env bash
# Install or update the 1Password desktop app on Linux.
# x86_64 uses the RPM repo (fedora.sh adds it). aarch64 has no package, only a
# tarball, and the app does not tell you when it is out of date; re-run this
# script to update.
set -euo pipefail

if [[ $(uname -m) != aarch64 ]]; then
  sudo dnf install -y 1password
  exit
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz |
  tar -xz -C "$tmp"
src=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name '1password-*' | head -1)
[[ -n $src ]] || { echo 'Unexpected 1Password tarball layout' >&2; exit 1; }

sudo rm -rf /opt/1Password
sudo mv "$src" /opt/1Password
sudo /opt/1Password/after-install.sh
echo "1Password installed: $(/opt/1Password/1password --version 2>/dev/null || echo /opt/1Password)"
