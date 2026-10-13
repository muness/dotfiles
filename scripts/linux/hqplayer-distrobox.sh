#!/usr/bin/env bash
# Run HQPlayer Desktop's Debian arm64 build on Fedora via a Debian distrobox.
# Signalyst ships Desktop for Debian 13 / RPi OS arm64 but not Fedora aarch64.
#
#   scripts/linux/hqplayer-distrobox.sh ~/Downloads/hqplayer5desktop_*_arm64.deb
#
# The .deb must live under $HOME (distrobox shares the home directory).
# Distrobox shares /dev, PipeWire and Wayland with the host, so USB DACs and
# the GUI work without extra flags. Untested with HQPlayer specifically.
set -euo pipefail

deb=$(realpath "${1:?usage: $0 <hqplayer arm64 .deb>}")
box=hqplayer
[[ $deb == "$HOME"/* ]] || { echo "Put the .deb under $HOME first." >&2; exit 2; }
command -v distrobox >/dev/null || { echo 'sudo dnf install distrobox' >&2; exit 2; }

distrobox list | grep -q " $box " ||
  distrobox create --yes --name "$box" --image docker.io/library/debian:13

distrobox enter "$box" -- sudo apt-get update
distrobox enter "$box" -- sudo apt-get install -y "$deb"

desktop=$(dpkg-deb -c "$deb" | grep -o '[^/ ]*\.desktop$' | head -1)
if [[ -n $desktop ]]; then
  distrobox enter "$box" -- distrobox-export --app "${desktop%.desktop}"
  echo "Exported ${desktop%.desktop} to the COSMIC app launcher."
else
  echo "No .desktop file in the package; run it with: distrobox enter $box -- <binary>"
fi
