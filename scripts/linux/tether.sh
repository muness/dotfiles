#!/usr/bin/env bash
# Install or update the latest upstream Tether AppImage for the current user.
set -euo pipefail
mode=install
force=0
for option in "$@"; do
  case $option in
    --check|--dry-run) mode=check ;;
    --download-only|--build-only) mode=download ;;
    --force) force=1 ;;
    *) echo "Unknown Tether option: $option" >&2; exit 2 ;;
  esac
done
case $(uname -m) in
  aarch64) arch=aarch64 ;;
  x86_64) arch=x86_64 ;;
  *) echo 'Tether does not support this architecture.' >&2; exit 2 ;;
esac
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IFS=$'\t' read -r tag url sha256 < <(python3 "$here/github-release-metadata.py" tether)
[[ -n ${tag:-} && -n ${url:-} && -n ${sha256:-} ]] || { echo 'Could not resolve Tether release.' >&2; exit 1; }
version=${tag#v}
dir="$HOME/.local/opt/tether"
app="$dir/tether-$version-$arch.AppImage"
installed=$(sed -n 's|^Exec=".*/tether-\([0-9.]*\)-[^/]*.AppImage"$|\1|p' "$HOME/.local/share/applications/tether.desktop" 2>/dev/null || true)
if [[ $mode == check ]]; then
  if [[ $installed == "$version" && $force == 0 ]]; then
    echo "tether: installed $installed; current (upstream $version)"
  else
    echo "tether: installed ${installed:-none}; would update to $version"
  fi
  exit 0
fi
mkdir -p "$dir" "$HOME/.local/share/applications"
if [[ ! -f $app ]] || ! printf '%s  %s\n' "$sha256" "$app" | sha256sum -c --status; then
  tmp=$(mktemp "$dir/.tether-download.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  curl -fL --retry 3 "$url" -o "$tmp"
  printf '%s  %s\n' "$sha256" "$tmp" | sha256sum -c --status || { echo 'Tether checksum mismatch.' >&2; exit 1; }
  chmod 755 "$tmp"
  mv "$tmp" "$app"
fi
chmod 755 "$app"
if [[ $mode == download ]]; then
  echo "Downloaded and verified: $app"
  exit 0
fi
if [[ $force == 0 ]] && [[ -f $HOME/.local/share/applications/tether.desktop ]] &&
   grep -Fxq "Exec=\"$app\"" "$HOME/.local/share/applications/tether.desktop" &&
   systemctl --user is-active --quiet tetherd.service; then
  echo "Tether $version is already installed and running."
  exit 0
fi
"$app" --install-service
systemctl --user daemon-reload
systemctl --user enable --now tetherd.service
systemctl --user restart tetherd.service
cat > "$HOME/.local/share/applications/tether.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Tether
Comment=Connect an iPhone to Linux
Exec="$app"
Icon=phone
Terminal=false
Categories=Network;Utility;
EOF
echo 'Tether installed. Run its --bt-setup command before pairing an iPhone.'
