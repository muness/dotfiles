#!/usr/bin/env bash
# Install/update the current stable Zed build through the common vendor updater.
set -euo pipefail
mode=install
force=0
for option in "$@"; do
  case $option in
    --check|--dry-run) mode=check ;;
    --download-only|--build-only) mode=download ;;
    --force) force=1 ;;
    *) echo "Unknown Zed option: $option" >&2; exit 2 ;;
  esac
done
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IFS=$'\t' read -r tag url sha256 < <(python3 "$here/github-release-metadata.py" zed)
[[ -n ${tag:-} && -n ${url:-} && -n ${sha256:-} ]] || { echo 'Could not resolve Zed release.' >&2; exit 1; }
version=${tag#v}
installed=
if [[ -x $HOME/.local/zed.app/bin/zed ]]; then
  installed=$("$HOME/.local/zed.app/bin/zed" --version | awk '{print $2}')
fi
if [[ $installed == "$version" && $force == 0 ]]; then
  echo "zed: installed $installed; current (upstream $version)"
  [[ $mode == download ]] || exit 0
elif [[ $mode == check ]]; then
  echo "zed: installed ${installed:-none}; would update to $version"
  exit 0
fi
cache=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/vendor-apps/zed/$version
mkdir -p "$cache"
archive=$cache/zed-linux-$(uname -m).tar.gz
if [[ ! -f $archive ]] || ! printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c --status; then
  curl -fL --retry 3 "$url" -o "$archive.part"
  printf '%s  %s\n' "$sha256" "$archive.part" | sha256sum -c --status || { echo 'Zed checksum mismatch.' >&2; exit 1; }
  mv "$archive.part" "$archive"
fi
if [[ $mode == download ]]; then
  echo "Downloaded and verified: $archive"
  exit 0
fi
# Use the vendor's integration logic with the already verified bundle.
curl -fsSL --retry 3 https://zed.dev/install.sh -o "$cache/install.sh"
ZED_BUNDLE_PATH="$archive" ZED_VERSION="$version" ZED_CHANNEL=stable sh "$cache/install.sh"
