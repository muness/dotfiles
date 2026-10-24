# Official Linux ARM64 binary, repackaged for pacman ownership and removal.
# Update the version, URL and checksum together after reviewing a new release.
pkgname=browseros-neo-bin
pkgver=0.51.2.3
pkgrel=1
pkgdesc='BrowserOS neo browser for external AI agents (official ARM64 binary)'
arch=('aarch64')
url='https://github.com/browseros-ai/BrowserOS'
license=('AGPL-3.0-only')
depends=('glibc' 'glib2' 'nss' 'nspr' 'libx11' 'at-spi2-core' 'libcups'
         'alsa-lib' 'libdrm' 'mesa' 'pango' 'cairo' 'systemd-libs'
         'libxcomposite' 'libxdamage' 'libxrandr' 'libxkbcommon' 'gtk3'
         'xdg-utils')
options=('!strip' '!debug')
source=("browseros-neo-${pkgver}-arm64.deb::https://github.com/browseros-ai/BrowserOS/releases/download/browserclaw/v${pkgver}/BrowserOS_neo_v${pkgver}_arm64.deb")
sha256sums=('699cbbffec1a5dcb70a7647076d4c5731f5eb1f991c35f5c2319a24e5847a994')

package() {
  tar -xf "$srcdir/data.tar.zst" -C "$pkgdir"
  # Match the vendor's postinst sandbox permissions. Pacman owns the files as root.
  chmod 4755 "$pkgdir/usr/lib/browserclaw/chrome_sandbox"
  # Use the native Wayland path on the target Asahi desktop.
  sed -i 's|^Exec=/usr/bin/browserclaw %U$|Exec=/usr/bin/browserclaw --ozone-platform=wayland %U|' \
    "$pkgdir/usr/share/applications/browserclaw.desktop"
}
