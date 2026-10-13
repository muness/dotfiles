#!/usr/bin/env bash
# Check the shared /Volumes/src on whichever OS is running. Read-only unless
# --fix-ownership is given (Linux, root): that re-owns stray files on disk to
# the Mac user so both sides can write them.
set -uo pipefail

mountpoint=${SRC_MOUNTPOINT:-/Volumes/src}
mac_uid=501
mac_gid=20
fix=0
[[ ${1:-} == --fix-ownership ]] && fix=1
problems=0
warn() { echo "  ! $*"; problems=$((problems + 1)); }
ok() { echo "  ✓ $*"; }

echo "Shared src on $(uname -s):"
if [[ ! -d $mountpoint ]] || ! { mount | grep -q " on $mountpoint "; }; then
  warn "$mountpoint is not mounted"
  exit 1
fi
ok "$mountpoint mounted"

if [[ $(uname -s) == Linux ]]; then
  opts=$(findmnt -no OPTIONS "$mountpoint")
  if [[ $(findmnt -no FSTYPE "$mountpoint") == ext4 ]]; then ok "ext4"; else warn "not ext4"; fi
  if [[ $opts == *idmapped* || $(id -u) == "$mac_uid" ]]; then ok "uid mapping in place"; else warn "no idmap and uid $(id -u) != $mac_uid"; fi
  features=$(dumpe2fs -h "$(findmnt -no SOURCE "$mountpoint")" 2>/dev/null | sed -n 's/^Filesystem features: *//p')
  if [[ -n $features ]]; then
    for bad in metadata_csum inline_data bigalloc meta_bg journal_dev orphan_file; do
      [[ " $features " == *" $bad "* ]] && warn "ext4 feature '$bad' is unsupported by Paragon extFS"
    done
  fi
else
  if diskutil info "$mountpoint" | grep -q 'Owners:.*Enabled'; then ok "ownership enabled"; else warn "ownership ignored: sudo diskutil enableOwnership $mountpoint"; fi
  [[ $(id -u) == "$mac_uid" ]] || warn "macOS uid is $(id -u), Linux mount maps $mac_uid; re-run src-mount-linux.sh --mac-uid $(id -u)"
fi

# Files the current user cannot claim, i.e. written with the wrong owner.
strays=$(find "$mountpoint" -xdev -mindepth 1 -not -path "$mountpoint/lost+found*" ! -user "$(id -u)" -print 2>/dev/null | head -20)
if [[ -n $strays ]]; then
  warn "files not owned by $(id -un) (first 20):"
  printf '      %s\n' "$strays"
  if ((fix)) && [[ $(uname -s) == Linux && $EUID == 0 ]]; then
    probe=$(mktemp -d)
    mount "$(findmnt -no SOURCE "$mountpoint")" "$probe"
    find "$probe" -xdev -mindepth 1 -not -path "$probe/lost+found*" \( ! -uid "$mac_uid" -o ! -gid "$mac_gid" \) -exec chown -h "$mac_uid:$mac_gid" {} +
    umount "$probe"; rmdir "$probe"
    ok "re-owned to $mac_uid:$mac_gid on disk"
    problems=$((problems - 1))
  else
    echo "      fix on Linux: sudo $0 --fix-ownership"
  fi
else
  ok "all files owned by $(id -un)"
fi

# Per-OS build output that leaked into the shared tree.
for name in target node_modules .venv; do
  n=$(find "$mountpoint" -xdev -maxdepth 4 -type d -name "$name" -prune -print 2>/dev/null | wc -l | tr -d ' ')
  ((n)) && echo "  · $n '$name' dirs in $mountpoint (built for one OS; rebuild after switching)"
done
case ${CARGO_TARGET_DIR:-} in
  "$mountpoint"*) warn "CARGO_TARGET_DIR points inside $mountpoint" ;;
esac

((problems)) && { echo "$problems problem(s)"; exit 1; }
echo "All good."
