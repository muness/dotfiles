#!/usr/bin/env bash
# Build the current stable Bazecor release natively; upstream Linux binaries are x64.
set -euo pipefail
mode=install
force=0
for option in "$@"; do
  case $option in
    --check|--dry-run) mode=check ;;
    --download-only) mode=download ;;
    --build-only) mode=build ;;
    --force) force=1 ;;
    *) echo "Unknown Bazecor option: $option" >&2; exit 2 ;;
  esac
done
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tag=$(curl -fsSL --retry 3 --max-time 30 https://api.github.com/repos/Dygmalab/Bazecor/releases/latest |
  python3 -c 'import json,re,sys; r=json.load(sys.stdin); t=r.get("tag_name", ""); assert re.fullmatch(r"v\d+(?:\.\d+)+", t) and not r.get("draft") and not r.get("prerelease"), "Expected stable Bazecor release"; print(t)')
version=${tag#v}
installed=$(pacman -Q bazecor 2>/dev/null | cut -d' ' -f2) || installed=
if [[ $mode == check ]]; then
  if [[ -n $installed && $force == 0 ]] && (( $(vercmp "${installed%-*}" "$version") >= 0 )); then
    echo "bazecor: installed $installed; current (upstream $version)"
  else
    echo "bazecor: installed ${installed:-none}; would update to $version (native source build)"
  fi
  exit 0
fi
# shellcheck disable=SC1091
. /etc/os-release
[[ " ${ID:-} ${ID_LIKE:-} " == *' arch '* || ${ID:-} == archarm || ${ID:-} == alarm ]] || { echo 'Bazecor packaging requires Arch.' >&2; exit 2; }
((EUID != 0)) || { echo 'Run as your desktop user.' >&2; exit 2; }
if [[ $mode == install && -n $installed && $force == 0 ]] && (( $(vercmp "${installed%-*}" "$version") >= 0 )); then
  echo "Bazecor $installed is already current."
  exit 0
fi
cache=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/vendor-apps/bazecor/$version/$(uname -m)
mkdir -p "$cache"
exec 9>"$cache/update.lock"
flock -n 9 || { echo 'A Bazecor update is already running.' >&2; exit 1; }
source_dir=$cache/source
if [[ ! -d $source_dir/.git ]]; then
  git clone --depth 1 --branch "$tag" https://github.com/Dygmalab/Bazecor.git "$source_dir"
fi
[[ -z $(git -C "$source_dir" status --porcelain --untracked-files=no) ]] || { echo 'Bazecor source has local edits.' >&2; exit 1; }
[[ $(git -C "$source_dir" rev-parse HEAD) == "$(git -C "$source_dir" rev-parse "$tag^{commit}")" ]] || { echo 'Bazecor source does not match release.' >&2; exit 1; }
git -C "$source_dir" rev-parse HEAD >"$cache/source-commit"
if [[ $mode == download ]]; then
  echo "Downloaded release source: $source_dir ($tag)"
  exit 0
fi
if [[ $mode == install ]]; then
  pkexec /usr/bin/pacman -Syu --needed --noconfirm base-devel python libarchive gtk3 nss alsa-lib libxss libxtst libxkbcommon systemd-libs
fi
command -v mise >/dev/null || { echo 'Install mise first (Bazecor needs its upstream build runtime).' >&2; exit 2; }
# Derive the build runtime from this release's CI, then use its newest patch.
# Old Electron Forge fails to finish packaging under a newer global Node major.
build_node=$(python3 - "$source_dir/.github/workflows/release.yml" <<'PYNODE'
import re, sys
from pathlib import Path
majors = set(re.findall(r"node-version:\s*['\"]?(\d+)(?:\.\d+)*", Path(sys.argv[1]).read_text()))
if len(majors) != 1:
    raise SystemExit('Expected one upstream Bazecor build Node major')
print(majors.pop())
PYNODE
)
mise install "node@$build_node"
case $(uname -m) in aarch64) electron_arch=arm64 ;; x86_64) electron_arch=x64 ;; *) exit 2 ;; esac
(
  cd "$source_dir"
  # Honor the release's own yarn.lock, including its Electron/native-module ABI.
  mise exec "node@$build_node" -- npx --yes --package yarn yarn install --frozen-lockfile --non-interactive
  mise exec "node@$build_node" -- npm run package -- --platform=linux --arch="$electron_arch"
)
bundle=$source_dir/out/Bazecor-linux-$electron_arch
[[ -x $bundle/Bazecor ]] || { echo 'Native Bazecor bundle was not produced.' >&2; exit 1; }
cp "$here/vendor-packages/bazecor.desktop" "$here/vendor-packages/60-dygma.rules" "$cache/"
sed "s/@VERSION@/$version/" "$here/vendor-packages/bazecor.PKGBUILD" >"$cache/PKGBUILD"
(
  cd "$cache"
  export BAZECOR_BUNDLE="$bundle" BAZECOR_ICON="$source_dir/build/logo.png"
  makepkg --force --noconfirm
  mapfile -t packages < <(makepkg --packagelist)
  ((${#packages[@]} == 1)) && [[ -f ${packages[0]} ]] || exit 1
  if [[ $mode == install ]]; then
    pkexec /usr/bin/pacman -U --noconfirm "${packages[0]}"
    pkexec /usr/bin/udevadm control --reload-rules
  else
    printf 'Built: %s\n' "${packages[0]}"
  fi
)
