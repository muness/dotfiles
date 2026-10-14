#!/usr/bin/env bash
# Install the complete published Aurora stack on Arch ARM. Never build a kernel
# here or apply Arch packages to Fedora. Review release + checksum together.
set -euo pipefail

release=aurora-2026.10.13.18
installer_sha256=f875b38a9c3e5946655b7542433cbcab6f6dd519d179f50421940f3236d701d3
url="https://github.com/omacom/linux-aurora/releases/download/$release/install-aurora-sep.sh"
mode=${1:---read-only}
case $mode in
  --check|--read-only|--enable-touchid) ;;
  --help|-h)
    echo 'Usage: aurora.sh [--check|--read-only|--enable-touchid]'
    echo "Published release: $release"
    echo 'Read-only prevents SEP writes; kernel and boot components are still replaced.'
    exit 0 ;;
  *) echo "Unknown Aurora option: $mode" >&2; exit 2 ;;
esac
(($# <= 1)) || { echo 'Expected one Aurora option.' >&2; exit 2; }
[[ $(uname -s) == Linux && $(uname -m) == aarch64 ]] ||
  { echo 'Aurora requires Linux on aarch64 Apple Silicon.' >&2; exit 2; }
# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" arch "*|*" archarm "*|*" alarm "*) ;;
  *) echo 'Use Aurora on the fresh Arch ARM installation; this script cannot install it on this OS.' >&2; exit 2 ;;
esac
command -v pacman >/dev/null || { echo 'pacman is required.' >&2; exit 2; }
if [[ ! -r /proc/device-tree/compatible ]] || ! grep -aq 'apple,arm-platform' /proc/device-tree/compatible; then
  echo 'Aurora requires a native Apple Silicon installation, not an ARM VM.' >&2
  exit 2
fi
[[ $mode == --check ]] && exit 0

download=$(mktemp -d)
trap 'rm -rf "$download"' EXIT
curl -fSL --retry 3 "$url" -o "$download/install-aurora-sep.sh"
printf '%s  %s\n' "$installer_sha256" "$download/install-aurora-sep.sh" | sha256sum --check --status ||
  { echo 'Aurora installer checksum mismatch; review the release before updating its pin.' >&2; exit 1; }

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/aurora
mkdir -p "$state_dir"
install -m 600 "$download/install-aurora-sep.sh" "$state_dir/$release.sh"
printf '%s\n' "$release $installer_sha256 $mode" >"$state_dir/last-request"
echo "Installing $release ($mode); upstream manages kernel, m1n1, DTBs, calibration and libfprint."
if [[ $mode == --read-only ]]; then
  bash "$state_dir/$release.sh" --read-only
else
  # Upstream preserves an earlier read-only configuration. Its owner must
  # deliberately remove that setting before enrollment; do not bypass it here.
  bash "$state_dir/$release.sh"
fi
printf '%s\n' "$release $installer_sha256 $mode" >"$state_dir/last-success"
echo 'Reboot before testing the dock or running aurora-touchid-setup.'
