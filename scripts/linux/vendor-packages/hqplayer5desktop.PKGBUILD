pkgname=hqplayer5desktop
pkgver=@VERSION@
pkgrel=@REVISION@
pkgdesc='HQPlayer 5 Desktop high quality audio player (native vendor build)'
arch=('aarch64' 'x86_64')
url='https://signalyst.com/hqplayer-desktop/'
license=('custom:Proprietary')
depends=(alsa-lib gcc-libs gmp lame libglvnd libmicrohttpd libogg libusb-compat
         mpfr mpg123 openmp qt6-base qt6-charts qt6-declarative qt6-positioning
         qt6-svg qt6-webchannel qt6-webengine qt6-webview systemd-libs)
optdepends=('evince: open the included manual')
conflicts=('hqplayer5client')
options=('!strip' '!debug')
source=('vendor.deb::@URL@')
noextract=('vendor.deb')
sha256sums=('@SHA256@')
package() {
  set -o pipefail
  local payload binary
  payload=$(bsdtar -tf vendor.deb | grep -E '^data\.tar\.(xz|gz|zst)$')
  bsdtar -xOf vendor.deb "$payload" | bsdtar --no-same-owner -xf - -C "$pkgdir"
  install -dm755 "$pkgdir/opt/hqplayer5desktop/bin" "$pkgdir/opt/hqplayer5desktop/lib"
  # Debian's libomp soname differs from Arch. Keep compatibility private to HQPlayer.
  ln -s /usr/lib/libomp.so "$pkgdir/opt/hqplayer5desktop/lib/libomp.so.5"
  for binary in hqp5-control hqplayer5client hqplayer5desktop; do
    mv "$pkgdir/usr/bin/$binary" "$pkgdir/opt/hqplayer5desktop/bin/$binary.bin"
    printf '#!/bin/sh\nLD_LIBRARY_PATH="/opt/hqplayer5desktop/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec /opt/hqplayer5desktop/bin/%s.bin "$@"\n' "$binary" >"$pkgdir/usr/bin/$binary"
    chmod 755 "$pkgdir/usr/bin/$binary"
  done
  install -Dm644 "$pkgdir/usr/share/doc/hqplayer5desktop/copyright" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
