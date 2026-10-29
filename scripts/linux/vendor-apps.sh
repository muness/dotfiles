#!/usr/bin/env bash
# Repackage official native vendor binaries for Arch; no AUR helper/repo needed.
# --check and --download-only also work on Fedora for inspecting the artifacts.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mode=install
force=0
apps=()
while (($#)); do
  case $1 in
    --check|--dry-run) mode=check ;;
    --download-only) mode=download ;;
    --build-only) mode=build ;;
    --force) force=1 ;;
    chatgpt|chrome|claude|browseros) apps+=("$1") ;;
    --help|-h)
      echo 'Usage: vendor-apps.sh [--check|--dry-run|--download-only|--build-only] [--force] [chatgpt|chrome|claude|browseros]'
      echo 'Default: check vendor feeds, build newer versions, install with pacman.'
      echo '--check/--dry-run compares installed packages without downloading or installing.'
      exit 0 ;;
    *) echo "Unknown vendor-app option: $1" >&2; exit 2 ;;
  esac
  shift
done
((${#apps[@]})) || { apps=(chatgpt chrome claude); [[ $(uname -m) != aarch64 ]] || apps+=(browseros); }
arch=$(uname -m)
case $arch in aarch64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 2 ;; esac

if [[ $mode == install || $mode == build ]]; then
  ((EUID != 0)) || { echo 'Run as your regular user; makepkg refuses root builds.' >&2; exit 2; }
  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *" arch "*|*" archarm "*|*" alarm "*) ;;
    *) echo 'Building/installing these packages requires Arch Linux; use --check or --download-only here.' >&2; exit 2 ;;
  esac
  if [[ $mode == install ]]; then
    # A full upgrade precedes dependency installation: never refresh one package
    # against an older Arch system. These map the vendors' runtime requirements.
    pkexec /usr/bin/pacman -Syu --needed --noconfirm base-devel libarchive python \
      alsa-lib at-spi2-core bash ca-certificates cairo curl dbus expat gcc-libs \
      gdk-pixbuf2 glib2 glibc gtk3 libcups libdrm libglvnd libnotify libusb \
      libx11 libxcb libxcomposite libxdamage libxext libxfixes libxkbcommon \
      libxrandr libxss libxtst libsecret pipewire mesa nspr nss openssl pango systemd-libs \
      tpm2-tss ttf-liberation vulkan-icd-loader wget xdg-utils xz
  fi
  command -v makepkg >/dev/null || { echo 'makepkg is required (base-devel).' >&2; exit 2; }
fi

cache_root=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/vendor-apps
for app in "${apps[@]}"; do
  metadata=$(python3 "$here/vendor-app-metadata.py" "$app" "$arch" --tsv)
  IFS=$'\t' read -r package version pkgver pkgrel url sha256 size <<<"$metadata"
  if [[ $mode == check ]]; then
    if ! command -v pacman >/dev/null || ! command -v vercmp >/dev/null; then
      echo "$app: latest $pkgver-$pkgrel ($arch); installed version unavailable on this system"
    else
      installed=$(pacman -Q "$package" 2>/dev/null | cut -d' ' -f2) || installed=
      if [[ -z $installed ]]; then
        echo "$app: not installed; would install $pkgver-$pkgrel ($size bytes)"
      elif [[ $force == 1 ]]; then
        echo "$app: installed $installed; would rebuild and install $pkgver-$pkgrel (--force)"
      elif (( $(vercmp "$installed" "$pkgver-$pkgrel") < 0 )); then
        echo "$app: installed $installed; would update to $pkgver-$pkgrel ($size bytes)"
      else
        echo "$app: installed $installed; current (vendor $pkgver-$pkgrel)"
      fi
    fi
    continue
  fi
  echo "$app: vendor version $version, $arch, $size bytes"
  if [[ $mode == install && $force == 0 ]]; then
    installed=$(pacman -Q "$package" 2>/dev/null | cut -d' ' -f2) || installed=
    if [[ -n $installed ]] && (( $(vercmp "$installed" "$pkgver-$pkgrel") >= 0 )); then
      echo "$package $installed is already current (or newer)."
      continue
    fi
  fi
  build_dir=$cache_root/$app/$version/$arch
  mkdir -p "$build_dir"
  artifact=$build_dir/vendor.deb
  if [[ ! -f $artifact ]] || ! printf '%s  %s\n' "$sha256" "$artifact" | sha256sum --check --status; then
    curl -fSL --retry 3 "$url" -o "$artifact.part"
    printf '%s  %s\n' "$sha256" "$artifact.part" | sha256sum --check --status ||
      { echo "Vendor checksum mismatch for $app; nothing installed." >&2; exit 1; }
    mv "$artifact.part" "$artifact"
  fi
  echo "Verified vendor archive: $artifact"
  [[ $mode == download ]] && continue

  launcher_sha=
  if [[ $app != browseros ]]; then
    cp "$here/vendor-packages/$app-launcher.sh" "$build_dir/launcher.sh"
    launcher_sha=$(sha256sum "$build_dir/launcher.sh" | cut -d' ' -f1)
  fi
  python3 - "$here/vendor-packages/$app.PKGBUILD" "$build_dir/PKGBUILD" \
    "$pkgver" "$pkgrel" "$url" "$sha256" "$launcher_sha" <<'PY'
from pathlib import Path
import sys
source, destination, version, revision, url, digest, launcher = sys.argv[1:]
recipe = Path(source).read_text()
for token, value in zip(("@VERSION@", "@REVISION@", "@URL@", "@SHA256@", "@LAUNCHER_SHA256@"),
                        (version, revision, url, digest, launcher)):
    recipe = recipe.replace(token, value)
Path(destination).write_text(recipe)
PY
  (
    cd "$build_dir"
    makepkg --force --noconfirm
    mapfile -t packages < <(makepkg --packagelist)
    ((${#packages[@]} == 1)) && [[ -f ${packages[0]} ]] ||
      { echo "Expected one built $app package." >&2; exit 1; }
    if [[ $mode == install ]]; then
      pkexec /usr/bin/pacman -U --noconfirm "${packages[0]}"
      pacman -Q "$package"
    else
      printf 'Built: %s\n' "${packages[0]}"
    fi
  )
done
