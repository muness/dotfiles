#!/usr/bin/env bash
# Install or update the 1Password desktop app on Linux.
# Fedora x86_64 uses the RPM repo. Arch and Linux aarch64 use the vendor tarball;
# re-run this script to update it. The CLI comes from the shared mise config.
set -euo pipefail

# shellcheck disable=SC1091
. /etc/os-release
if [[ $(uname -m) != aarch64 && " ${ID:-} ${ID_LIKE:-} " == *" fedora "* ]]; then
  sudo dnf install -y 1password
  exit
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
case $(uname -m) in
  aarch64|x86_64) arch=$(uname -m) ;;
  *) echo 'No 1Password desktop tarball configured for this architecture.' >&2; exit 2 ;;
esac
curl -fsSL "https://downloads.1password.com/linux/tar/stable/$arch/1password-latest.tar.gz" |
  tar -xz -C "$tmp"
src=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name '1password-*' | head -1)
[[ -n $src ]] || { echo 'Unexpected 1Password tarball layout' >&2; exit 1; }

sudo rm -rf /opt/1Password
sudo mv "$src" /opt/1Password
sudo /opt/1Password/after-install.sh
echo "1Password installed: $(/opt/1Password/1password --version 2>/dev/null || echo /opt/1Password)"
