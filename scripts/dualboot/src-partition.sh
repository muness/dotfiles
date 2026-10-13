#!/usr/bin/env bash
# Create the shared ext4 "src" partition in the free space the Asahi installer
# left behind. Run on Linux as root. Prints the plan and changes nothing unless
# --yes is given.
#
#   sudo scripts/dualboot/src-partition.sh            # dry run
#   sudo scripts/dualboot/src-partition.sh --yes      # do it
#
# The filesystem omits ext4 features Paragon extFS for Mac cannot handle
# (metadata_csum and friends), so macOS can mount it read-write.
set -euo pipefail

label=src
min_gib=100
apply=0
while (($#)); do
  case $1 in
    --yes) apply=1 ;;
    --min-gib) min_gib=$2; shift ;;
    *) echo "usage: $0 [--yes] [--min-gib N]" >&2; exit 2 ;;
  esac
  shift
done

[[ $(uname -s) == Linux ]] || { echo 'Run this on the Linux side.' >&2; exit 2; }
((EUID == 0)) || { echo 'Run as root (sudo).' >&2; exit 2; }
for tool in sgdisk partprobe mkfs.ext4 dumpe2fs lsblk; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing $tool (dnf install gdisk e2fsprogs parted)" >&2; exit 2; }
done

if blkid -L "$label" >/dev/null 2>&1 || [[ -e /dev/disk/by-partlabel/$label ]]; then
  echo "A filesystem or partition labelled '$label' already exists:" >&2
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$(blkid -L "$label" 2>/dev/null || echo /dev/disk/by-partlabel/$label)" >&2
  exit 1
fi

# The disk that holds the running root filesystem is the internal NVMe.
root_part=$(findmnt -no SOURCE / | sed 's/\[.*//')
disk=/dev/$(lsblk -no PKNAME "$root_part" | head -1)
[[ -b $disk ]] || { echo "Could not determine the disk for $root_part" >&2; exit 1; }

sector=$(blockdev --getss "$disk")
first=$(sgdisk -F "$disk" | tail -1)
last=$(sgdisk -E "$disk" | tail -1)
free_gib=$(( (last - first + 1) * sector / 1024 / 1024 / 1024 ))

echo "Disk: $disk (sector size $sector)"
sgdisk -p "$disk" | sed -n '/^Number/,$p'
echo
echo "Largest free block: sectors $first-$last, about ${free_gib} GiB"

if ((free_gib < min_gib)); then
  echo "That is less than --min-gib $min_gib. Did the Asahi installer use all free space?" >&2
  exit 1
fi

cat <<PLAN

Plan:
  1. sgdisk -n 0:$first:$last -t 0:8300 -c 0:$label $disk   (new Linux partition)
  2. sgdisk -s $disk                                          (sort entries; Apple tools dislike unsorted GPTs)
  3. mkfs.ext4 -L $label -m 1 -O ^metadata_csum,^metadata_csum_seed,^orphan_file <new partition>

Existing partitions are not modified. The APFS and Recovery partitions stay put.
PLAN

if ((apply == 0)); then
  echo
  echo 'Dry run. Re-run with --yes to apply.'
  exit 0
fi

sgdisk -n "0:$first:$last" -t 0:8300 -c "0:$label" "$disk"
sgdisk -s "$disk"
partprobe "$disk"
udevadm settle

part=$(readlink -f "/dev/disk/by-partlabel/$label")
[[ -b $part ]] || { echo "Partition was created but /dev/disk/by-partlabel/$label did not appear" >&2; exit 1; }

mkfs.ext4 -L "$label" -m 1 -O ^metadata_csum,^metadata_csum_seed,^orphan_file "$part"

echo
echo "Created $part:"
dumpe2fs -h "$part" 2>/dev/null | grep -E '^(Filesystem volume name|Filesystem features|Block size)'
echo
echo "Next: sudo scripts/dualboot/src-mount-linux.sh"
