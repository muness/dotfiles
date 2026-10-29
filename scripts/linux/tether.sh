#!/usr/bin/env bash
# Install or update the latest upstream Tether AppImage for the current user.
set -euo pipefail
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
if [[ -f $HOME/.local/share/applications/tether.desktop ]] &&
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
