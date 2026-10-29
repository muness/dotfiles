# Repackage the current official Linux ARM64 build for pacman.
pkgname=browseros-neo-bin
pkgver=@VERSION@
pkgrel=@REVISION@
pkgdesc='BrowserOS neo browser for external AI agents (official ARM64 binary)'
arch=('aarch64')
url='https://github.com/browseros-ai/BrowserOS'
license=('AGPL-3.0-only')
depends=('glibc' 'glib2' 'nss' 'nspr' 'libx11' 'at-spi2-core' 'libcups'
         'alsa-lib' 'libdrm' 'mesa' 'pango' 'cairo' 'systemd-libs'
         'libxcomposite' 'libxdamage' 'libxrandr' 'libxkbcommon' 'gtk3' 'xdg-utils')
makedepends=('libarchive')
options=('!strip' '!debug')
source=('vendor.deb::@URL@')
noextract=('vendor.deb')
sha256sums=('@SHA256@')

package() {
  set -o pipefail
  local payload
  payload=$(bsdtar -tf vendor.deb | grep -E '^data\.tar\.(xz|gz|zst)$')
  [[ -n $payload ]] || return 1
  bsdtar -xOf vendor.deb "$payload" | bsdtar --no-same-owner -xf - -C "$pkgdir"
  chmod 4755 "$pkgdir/usr/lib/browserclaw/chrome_sandbox"
  sed -i 's|^Exec=/usr/bin/browserclaw %U$|Exec=/usr/bin/browserclaw --ozone-platform=wayland %U|' \
    "$pkgdir/usr/share/applications/browserclaw.desktop"
}
