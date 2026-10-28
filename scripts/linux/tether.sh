#!/usr/bin/env bash
# Install the pinned upstream Tether AppImage for the current user.
set -euo pipefail
version=0.2.43
case $(uname -m) in
  aarch64) arch=aarch64; sha256=c740e98a8f6803dbeada21ada72df2a8353c92a69790929133e88f9894260ebc ;;
  x86_64) arch=x86_64; sha256=da0654900a2d0141c5fc136c029e520a03a17ee91a64012c5098bbc7aad1770c ;;
  *) echo 'Tether does not support this architecture.' >&2; exit 2 ;;
esac
dir="$HOME/.local/opt/tether"
app="$dir/tether-$version-$arch.AppImage"
mkdir -p "$dir" "$HOME/.local/share/applications"
if [[ ! -f $app ]] || ! printf '%s  %s\n' "$sha256" "$app" | sha256sum -c --status; then
  tmp=$(mktemp "$dir/.tether-download.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  curl -fL --retry 3 "https://github.com/zackb/tether/releases/download/v$version/tether-$version-$arch.AppImage" -o "$tmp"
  printf '%s  %s\n' "$sha256" "$tmp" | sha256sum -c --status || { echo 'Tether checksum mismatch.' >&2; exit 1; }
  chmod 755 "$tmp"
  mv "$tmp" "$app"
fi
chmod 755 "$app"
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
