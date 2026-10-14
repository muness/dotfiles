#!/usr/bin/env bash
# One-machine maintenance helper for the authorized 2026-10-14 src shrink.
# Stored on Fedora root, outside src. Run from a terminal after closing src apps.
set -euo pipefail
umask 077
((EUID == 0)) || { echo 'Run with sudo from /home/muness.' >&2; exit 1; }
cd /home/muness
disk=/dev/nvme0n1
part=/dev/nvme0n1p7
state=/home/muness/.local/state/dotfiles/reinstall
archive=$state/src-before-shrink-20261014.tar
old_size=71938857
new_size=45724457
start=171026694
expected_guid=9ce4ecfa-dded-4ae5-9445-f9df7e16c6fa
[[ -s $archive && -s $archive.sha256 ]] || { echo 'Source backup/checksum missing.' >&2; exit 1; }
sha256sum --check "$archive.sha256"
[[ $(blockdev --getss "$disk") == 4096 ]] || { echo 'Unexpected logical sector size.' >&2; exit 1; }
[[ $(blkid -s TYPE -o value "$part") == ext4 && $(blkid -s LABEL -o value "$part") == src ]] ||
  { echo 'Source filesystem identity changed.' >&2; exit 1; }
[[ $(lsblk -dn -o PARTUUID "$part") == "$expected_guid" ]] ||
  { echo 'Source partition GUID changed.' >&2; exit 1; }
mkdir -p "$state"
run=$state/resize-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$run"
exec > >(tee "$run/log.txt") 2>&1
sgdisk --backup="$run/gpt.bin" "$disk"
sfdisk --dump "$disk" > "$run/partitions.txt"
sfdisk --json "$disk" > "$run/before.json"
size=$(python3 - "$run/before.json" "$part" "$start" "$old_size" "$new_size" <<'PY'
import json, sys
table = json.load(open(sys.argv[1]))['partitiontable']
assert table['label'] == 'gpt' and table['sectorsize'] == 4096
p = next(p for p in table['partitions'] if p['node'] == sys.argv[2])
assert p['start'] == int(sys.argv[3]), 'Partition start changed'
assert p['size'] in (int(sys.argv[4]), int(sys.argv[5])), 'Partition size changed'
print(p['size'])
PY
)
# Never force or lazily unmount. A busy mount stops the operation here.
if findmnt -rn -S "$part" >/dev/null; then
  umount /Volumes/src || {
    fuser -vm /Volumes/src || true
    echo 'Close all programs using src, then rerun this helper.' >&2
    exit 1
  }
fi
! findmnt -rn -S "$part" >/dev/null || { echo 'src is still mounted.' >&2; exit 1; }
check_fs() {
  local result=0
  # Preen routine fixes without requiring a terminal; exit statuses above 1
  # still stop the resize if manual filesystem repair is needed.
  e2fsck -f -p "$part" || result=$?
  ((result <= 1)) || { echo "Filesystem check requires attention (status $result)." >&2; exit 1; }
}
blkid "$part" > "$run/filesystem-before.txt"
dumpe2fs -h "$part" > "$run/ext4-before.txt"
check_fs
if [[ $size == "$old_size" ]]; then
  # Filesystem first. 170 GiB fits safely inside the new ~174.4 GiB partition.
  resize2fs "$part" 170G
  check_fs
  # -N preserves unspecified fields, including start, UUID, type, name, attrs.
  # Update only p7 size; preserve signatures; defer kernel notification to partx.
  printf ', %s\n' "$new_size" | sfdisk --no-reread --no-tell-kernel \
    --wipe never --wipe-partitions never -N 7 "$disk"
fi
sfdisk --json "$disk" > "$run/after.json"
python3 - "$run/before.json" "$run/after.json" "$part" "$new_size" <<'PY'
import json, sys
before, after = (json.load(open(p)) for p in sys.argv[1:3])
for p in before['partitiontable']['partitions']:
    if p['node'] == sys.argv[3]:
        p['size'] = int(sys.argv[4])
assert before == after, 'Partition-table changes differ from the planned p7 size change'
PY
sync
partx --update --nr 7 "$disk" || true
if [[ $(blockdev --getsize64 "$part") != "$((new_size * 4096))" ]]; then
  echo 'GPT is resized; kernel still has old geometry. Reboot, then rerun this helper.'
  echo 'Do not enlarge the filesystem before rebooting.'
  exit 0
fi
check_fs
resize2fs "$part"
check_fs
dumpe2fs -h "$part" > "$run/ext4-after.txt"
python3 - "$run/ext4-before.txt" "$run/ext4-after.txt" <<'PY'
import sys
def identity(path):
    return {k: v.strip() for line in open(path) if ':' in line
            for k, v in [line.split(':', 1)]
            if k in ('Filesystem UUID', 'Filesystem features')}
assert identity(sys.argv[1]) == identity(sys.argv[2]), 'Filesystem UUID/features changed'
PY
mount /Volumes/src
findmnt /Volumes/src
df -h /Volumes/src
sfdisk --list-free "$disk"
echo 'Completed: src reduced by exactly 100 GiB. Logs and GPT backup:' "$run"
