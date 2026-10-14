# Repackages Google's official stable Debian binary. Layout reference:
# https://github.com/omacom/omarchy-pkgs/tree/master/pkgbuilds/google-chrome
pkgname=google-chrome
pkgver=@VERSION@
pkgrel=@REVISION@
pkgdesc='Google Chrome stable, from Google'
arch=('aarch64' 'x86_64')
url='https://www.google.com/chrome/'
license=('custom:chrome')
depends=(alsa-lib at-spi2-core bash ca-certificates cairo curl dbus expat gcc-libs
  glib2 glibc gtk3 libcups libdrm libx11 libxcb libxcomposite libxdamage libxext
  libxfixes libxkbcommon libxrandr libxss libxtst mesa nspr nss pango
  systemd-libs ttf-liberation vulkan-icd-loader wget xdg-utils)
makedepends=(libarchive)
optdepends=('gnome-keyring: desktop credential storage' 'pipewire: Wayland screen sharing')
options=('!strip' '!debug')
source=('vendor.deb::@URL@' launcher.sh)
noextract=(vendor.deb)
sha256sums=('@SHA256@' '@LAUNCHER_SHA256@')

package() {
  set -o pipefail
  local payload icon
  payload=$(bsdtar -tf vendor.deb | grep -E '^data\.tar\.(xz|gz|zst)$')
  [[ -n $payload ]] || return 1
  bsdtar -xOf vendor.deb "$payload" | bsdtar --no-same-owner -xf - -C "$pkgdir"
  [[ -x $pkgdir/opt/google/chrome/chrome ]] || return 1
  rm -f "$pkgdir/usr/bin/google-chrome-stable" "$pkgdir/usr/bin/google-chrome"
  install -Dm755 launcher.sh "$pkgdir/usr/bin/google-chrome-stable"
  ln -s google-chrome-stable "$pkgdir/usr/bin/google-chrome"
  chmod 4755 "$pkgdir/opt/google/chrome/chrome-sandbox"
  for icon in 16 24 32 48 64 128 256; do
    install -Dm644 "$pkgdir/opt/google/chrome/product_logo_$icon.png" \
      "$pkgdir/usr/share/icons/hicolor/${icon}x${icon}/apps/google-chrome.png"
  done
  install -Dm644 "$pkgdir/opt/google/chrome/WidevineCdm/LICENSE" \
    "$pkgdir/usr/share/licenses/$pkgname/WidevineCdm-LICENSE"
  install -Dm644 "$pkgdir/usr/share/doc/google-chrome-stable/copyright" \
    "$pkgdir/usr/share/licenses/$pkgname/copyright"
  sed -i '/^Exec=/i StartupWMClass=Google-chrome' "$pkgdir/usr/share/applications/google-chrome.desktop"
  rm -rf "$pkgdir/etc/apt" "$pkgdir/etc/cron.daily" "$pkgdir/opt/google/chrome/cron" \
    "$pkgdir/usr/share/doc" "$pkgdir/usr/share/menu"
}
