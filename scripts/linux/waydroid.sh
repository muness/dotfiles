#!/usr/bin/env bash
# Opt-in Asahi Waydroid setup. Run as the desktop user; elevate individual steps.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mode=install
elevate=(pkexec)
for arg in "$@"; do
  case $arg in
    --launchers-only) mode=launchers ;;
    --check) mode=check ;;
    --sudo) elevate=(sudo) ;;
    --help|-h)
      echo 'Usage: waydroid.sh [--check|--launchers-only] [--sudo]'
      echo 'Opt-in Arch ARM/Asahi installation; existing Android images/data are preserved.'
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
((EUID != 0)) || { echo 'Run as the desktop user, not root.' >&2; exit 2; }
if [[ $mode == launchers ]]; then
  exec /usr/bin/python3 "$here/waydroid/install-launchers.py"
fi
[[ $(uname -s) == Linux && $(uname -m) == aarch64 ]] ||
  { echo 'Requires native ARM64 Asahi Linux.' >&2; exit 2; }
# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" arch "*|*" archarm "*|*" alarm "*) ;;
  *) echo 'Requires Arch Linux ARM.' >&2; exit 2 ;;
esac
if [[ ! -r /proc/device-tree/compatible ]] || ! grep -aq 'apple,arm-platform' /proc/device-tree/compatible; then
  echo 'Requires native Apple Silicon.' >&2
  exit 2
fi
[[ $(getconf PAGESIZE) == 16384 ]] || { echo 'Expected a 16 KB host kernel.' >&2; exit 2; }
kernel=$(uname -r)
[[ -d /usr/lib/modules/$kernel/build ]] ||
  { echo "Install headers matching the running kernel ($kernel) first." >&2; exit 2; }
[[ $mode == check ]] && { echo "Asahi host and headers ready: $kernel"; exit 0; }

echo 'Installing packages; graphical authentication may be requested.'
"${elevate[@]}" /usr/bin/pacman -S --needed --noconfirm waydroid dkms lld base-devel curl libnotify desktop-file-utils
if ! modinfo binder_linux >/dev/null 2>&1; then
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/waydroid
  mkdir -p "$cache/binder"
  cp "$here/waydroid/PKGBUILD" "$cache/binder/PKGBUILD"
  (
    cd "$cache/binder"
    makepkg --force --noconfirm
    mapfile -t packages < <(makepkg --packagelist)
    ((${#packages[@]} == 1)) && [[ -f ${packages[0]} ]]
    "${elevate[@]}" /usr/bin/pacman -U --noconfirm "${packages[0]}"
  )
  # pacman hooks can warn and return success even if a DKMS build failed.
  "${elevate[@]}" /usr/bin/dkms install binder/1 -k "$kernel"
fi
"${elevate[@]}" /usr/bin/modprobe binder_linux devices=binder,hwbinder,vndbinder
for device in binder hwbinder vndbinder; do
  [[ -c /dev/$device ]] || { echo "Missing /dev/$device; stopping before initialization." >&2; exit 1; }
done

if [[ ! -f /var/lib/waydroid/waydroid.cfg ]]; then
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/waydroid
  mkdir -p "$cache/images"
  base=https://github.com/HLM319/waydroid_asahi_patches/releases/download/23.2_2026-05-30
  for kind in system vendor; do
    case $kind in
      system) digest=8d5beb8afb75db3a0bfbf5e0e587ea18025da6e82d3025e7b11241ca24262602 ;;
      vendor) digest=f828df7dd4d86ec1687725a9d830095e9f4675b72d34ef95f8c079b79ee82fae ;;
    esac
    archive=$cache/$kind.img.tar.zst
    if ! [[ -f $archive ]] || ! printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status; then
      curl -fL --retry 3 "$base/$kind.img.tar.zst" -o "$archive.part"
      printf '%s  %s\n' "$digest" "$archive.part" | sha256sum --check --status ||
        { echo "Checksum mismatch for $kind; nothing initialized." >&2; exit 1; }
      mv "$archive.part" "$archive"
    fi
    tar --zstd -xf "$archive" -C "$cache/images" "$kind.img"
  done
  "${elevate[@]}" /usr/bin/python3 "$here/waydroid/host-setup.py" "$cache/images"
else
  "${elevate[@]}" /usr/bin/python3 "$here/waydroid/host-setup.py"
fi
/usr/bin/python3 "$here/waydroid/install-launchers.py"
echo 'Ready: open Waydroid from the app launcher. Use Shut Down Waydroid to stop Android completely.'
