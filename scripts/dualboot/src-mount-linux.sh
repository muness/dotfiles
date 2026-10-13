#!/usr/bin/env bash
# Mount the shared "src" ext4 partition at /Volumes/src on Linux, mapping the
# macOS owner onto the Linux user so both sides see the files as their own.
#
#   sudo scripts/dualboot/src-mount-linux.sh [--mac-uid 501] [--mac-gid 20]
#
# Why a mapping: macOS gives the first user uid 501 (group staff, gid 20);
# Fedora gives uid/gid 1000. ext4 stores raw numbers, so without help each OS
# sees the other's files as owned by a stranger. An idmapped mount
# (X-mount.idmap, util-linux 2.39+) translates 501<->1000 at the mount, leaving
# both the disk and the Linux account untouched. Files are stored as 501:20,
# exactly what macOS expects.
set -euo pipefail

label=src
mountpoint=${SRC_MOUNTPOINT:-/Volumes/src}
mac_uid=501
mac_gid=20
while (($#)); do
  case $1 in
    --mac-uid) mac_uid=$2; shift ;;
    --mac-gid) mac_gid=$2; shift ;;
    *) echo "usage: $0 [--mac-uid N] [--mac-gid N]" >&2; exit 2 ;;
  esac
  shift
done

((EUID == 0)) || { echo 'Run as root (sudo).' >&2; exit 2; }
user=${SUDO_USER:?run via sudo from your own account}
uid=$(id -u "$user")
gid=$(id -g "$user")
home=$(getent passwd "$user" | cut -d: -f6)

blkid -L "$label" >/dev/null || { echo "No filesystem labelled '$label'. Run src-partition.sh first." >&2; exit 1; }

# No X-mount.mkdir: util-linux refuses it from fstab ("operation permitted for
# root only"), so the mount point is created below instead.
options=defaults,noatime,nofail
if ((uid != mac_uid || gid != mac_gid)); then
  # u:<id on disk>:<id seen through the mount>:<count>. mount(8) words these
  # fields the other way round; this order is the one that works (verified
  # below). \040 is a space inside fstab.
  options+=",X-mount.idmap=u:$mac_uid:$uid:1\\040g:$mac_gid:$gid:1"
fi
entry="LABEL=$label $mountpoint ext4 $options 0 2"

if grep -qE "^[^#]*[[:space:]]${mountpoint}[[:space:]]" /etc/fstab; then
  echo "/etc/fstab already has an entry for $mountpoint:"
  grep -E "[[:space:]]${mountpoint}[[:space:]]" /etc/fstab
  echo "Expected: $entry"
else
  cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
  printf '%s\n' "$entry" >>/etc/fstab
  echo "Added to /etc/fstab: $entry"
fi

systemctl daemon-reload
mkdir -p "$mountpoint"
findmnt "$mountpoint" >/dev/null || mount "$mountpoint"

# A fresh filesystem's root belongs to root; hand it to the user (as stored on disk).
probe=$(mktemp -d)
trap 'umount "$probe" 2>/dev/null || true; rmdir "$probe"' EXIT
mount "LABEL=$label" "$probe"   # second, unmapped view of the same filesystem
[[ $(stat -c %u "$probe") == "$mac_uid" ]] || chown "$mac_uid:$mac_gid" "$probe"

# Verify: a file the user creates must look like theirs here and like the Mac
# user's on disk.
test_file=$mountpoint/.src-mount-check
sudo -u "$user" touch "$test_file"
seen=$(stat -c %u:%g "$test_file")
stored=$(stat -c %u:%g "$probe/.src-mount-check")
sudo -u "$user" rm -f "$test_file"
echo "Linux sees $seen (want $uid:$gid); disk stores $stored (want $mac_uid:$mac_gid)"
if [[ $seen != "$uid:$gid" || $stored != "$mac_uid:$mac_gid" ]]; then
  echo 'Ownership mapping is wrong; see docs/asahi-dual-boot.md, "uid fallback".' >&2
  exit 1
fi

if [[ ! -e $home/src ]]; then
  sudo -u "$user" ln -s "$mountpoint" "$home/src"
  echo "Linked $home/src -> $mountpoint"
elif [[ $(readlink -f "$home/src") != "$mountpoint" ]]; then
  echo "note: $home/src exists and is not a link to $mountpoint; left alone"
fi
echo "Mounted $mountpoint."
