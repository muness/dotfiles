#!/usr/bin/env bash
# Install or update the 1Password desktop app on Linux.
# Fedora x86_64 uses the RPM repo. Arch and Linux aarch64 use the vendor tarball;
# the common vendor updater updates it. The CLI comes from the shared mise config.
set -euo pipefail

mode=install
force=0
for option in "$@"; do
  case $option in
    --check|--dry-run) mode=check ;;
    --download-only|--build-only) mode=download ;;
    --force) force=1 ;;
    *) echo "Unknown 1Password option: $option" >&2; exit 2 ;;
  esac
done
# shellcheck disable=SC1091
. /etc/os-release
if [[ $(uname -m) != aarch64 && " ${ID:-} ${ID_LIKE:-} " == *" fedora "* ]]; then
  case $mode in
    check) dnf check-upgrade 1password && exit 0; result=$?; [[ $result == 100 ]] && exit 0; exit "$result" ;;
    download) echo 'Use dnf download 1password for the repository-managed RPM.' >&2; exit 2 ;;
    install) pkexec /usr/bin/dnf install -y 1password ;;
  esac
  exit
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
case $(uname -m) in
  aarch64|x86_64) arch=$(uname -m) ;;
  *) echo 'No 1Password desktop tarball configured for this architecture.' >&2; exit 2 ;;
esac
url="https://downloads.1password.com/linux/tar/stable/$arch/1password-latest.tar.gz"
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/1password
# The tarball endpoint has no release index. Its ETag identifies the published
# build without downloading 200 MB merely to check for an update.
headers=$(curl -fsSI --retry 3 --max-time 30 "$url")
etag=$(awk 'tolower($1) == "etag:" {gsub("\\r", ""); print $2}' <<<"$headers")
[[ -n $etag ]] || { echo '1Password did not advertise an ETag.' >&2; exit 1; }
installed=none
[[ ! -x /opt/1Password/1password ]] || installed=$(/opt/1Password/1password --version)
if [[ -x /opt/1Password/1password && -f $state_dir/installed-etag && $force == 0 ]] &&
   [[ $(cat "$state_dir/installed-etag") == "$etag" ]]; then
  echo "1password: installed $installed; current (stable vendor build)"
  [[ $mode == download ]] || exit 0
elif [[ $mode == check ]]; then
  echo "1password: installed $installed; would update to latest stable tarball (build not yet recorded or changed)"
  exit 0
fi
cache=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/vendor-apps/1password
mkdir -p "$cache"
# Record the GET response, so a release published between HEAD and GET cannot
# cause the installed build to be marked with the wrong ETag.
curl -fSL --retry 3 -D "$tmp/headers" "$url" -o "$cache/1password-latest.tar.gz.part"
mv "$cache/1password-latest.tar.gz.part" "$cache/1password-latest.tar.gz"
etag=$(awk 'tolower($1) == "etag:" {gsub("\\r", ""); print $2}' "$tmp/headers" | tail -1)
[[ -n $etag ]] || { echo '1Password download did not advertise an ETag.' >&2; exit 1; }
if [[ $mode == download ]]; then
  echo "Downloaded: $cache/1password-latest.tar.gz"
  exit 0
fi
tar -xzf "$cache/1password-latest.tar.gz" -C "$tmp"
src=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name '1password-*' | head -1)
[[ -n $src ]] || { echo 'Unexpected 1Password tarball layout' >&2; exit 1; }

# System authentication requires a root-owned application. Extraction as the
# regular user otherwise preserves user ownership when root moves the files.
# Do this before after-install.sh sets the helper groups and setgid bits.
# One authentication prompt; cancellation occurs before any files change.
# shellcheck disable=SC2016 # Expansion belongs to the privileged shell.
pkexec /usr/bin/bash -c '
  set -euo pipefail
  src=$1
  [[ -d $src && -x $src/1password && -f $src/after-install.sh ]]
  chown -R root:root "$src"
  rm -rf /opt/1Password
  mv "$src" /opt/1Password
  /opt/1Password/after-install.sh
' dotfiles-1password "$src"
mkdir -p "$state_dir"
printf '%s\n' "$etag" >"$state_dir/installed-etag"
echo "1Password installed: $(/opt/1Password/1password --version 2>/dev/null || echo /opt/1Password)"
