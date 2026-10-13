#!/usr/bin/env bash
# Prepare the shared ext4 /Volumes/src on macOS once Paragon extFS mounts it.
#   scripts/dualboot/src-macos.sh
set -euo pipefail

mountpoint=/Volumes/src

[[ $(uname -s) == Darwin ]] || { echo 'Run this on macOS.' >&2; exit 2; }
if [[ ! -d "/Library/Application Support/Paragon Software" ]]; then
  echo 'Paragon extFS is not installed (brew install --cask paragon-extfs).' >&2
  exit 1
fi
if ! mount | grep -q " on $mountpoint "; then
  cat >&2 <<MSG
$mountpoint is not mounted. Check:
  - Startup Security is "Reduced Security" with kernel extensions from
    identified developers allowed (recoveryOS > Startup Security Utility)
  - Paragon's kernel extension is approved under System Settings >
    Privacy & Security, then reboot
  - the extFS app shows the "src" volume and mounts it
MSG
  exit 1
fi

# External volumes ignore ownership by default, which would write files as
# uid 99. Linux maps uid $(id -u) onto its own user, so ownership must be real.
sudo diskutil enableOwnership "$mountpoint"

# Spotlight would index every node_modules and target dir on the volume.
sudo mdutil -i off "$mountpoint" >/dev/null
sudo touch "$mountpoint/.metadata_never_index"

if [[ ! -e $HOME/src ]]; then
  ln -s "$mountpoint" "$HOME/src"
  echo "Linked ~/src -> $mountpoint"
elif [[ $(readlink "$HOME/src" || true) != "$mountpoint" ]]; then
  echo "note: ~/src exists and is not a link to $mountpoint; left alone."
  echo "      Move its contents into $mountpoint, then: rm -r ~/src && ln -s $mountpoint ~/src"
fi

echo "uid $(id -u) gid $(id -g); Linux side must map to these (src-mount-linux.sh defaults: 501/20)."
"$(dirname -- "${BASH_SOURCE[0]}")/src-doctor.sh"
