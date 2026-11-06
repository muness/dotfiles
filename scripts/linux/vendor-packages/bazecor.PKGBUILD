pkgname=bazecor
pkgver=@VERSION@
pkgrel=2
pkgdesc='Dygma keyboard configurator, native ARM64 build'
arch=('aarch64' 'x86_64')
url='https://github.com/Dygmalab/Bazecor'
license=('GPL-3.0-only')
depends=('gtk3' 'nss' 'alsa-lib' 'libxss' 'libxtst' 'libxkbcommon' 'systemd-libs')
options=('!strip' '!debug')
package() {
  install -dm755 "$pkgdir/opt/bazecor" "$pkgdir/usr/bin"
  cp -a "${BAZECOR_BUNDLE:?}/." "$pkgdir/opt/bazecor/"
  chmod -R a+rX "$pkgdir/opt/bazecor"
  chmod 4755 "$pkgdir/opt/bazecor/chrome-sandbox"
  ln -s /opt/bazecor/Bazecor "$pkgdir/usr/bin/bazecor"
  install -Dm644 "$startdir/60-dygma.rules" "$pkgdir/etc/udev/rules.d/60-dygma.rules"
  install -Dm644 "${BAZECOR_ICON:?}" "$pkgdir/usr/share/icons/hicolor/512x512/apps/bazecor.png"
  install -Dm644 "$startdir/bazecor.desktop" "$pkgdir/usr/share/applications/bazecor.desktop"
}
