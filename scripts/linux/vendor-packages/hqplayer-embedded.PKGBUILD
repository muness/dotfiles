pkgname=hqplayer-embedded
pkgver=@VERSION@
pkgrel=@REVISION@
pkgdesc='Signalyst HQPlayer Embedded (native vendor build)'
arch=('aarch64' 'x86_64')
url='https://signalyst.com/configuring-hqplayer-embedded/'
license=('custom')
depends=(alsa-lib glibc libusb-compat flac gcc-libs zip unzip wavpack openmp mpg123 lame libmicrohttpd cairo)
install=hqplayer-embedded.install
backup=('etc/hqplayer/hqplayerd.xml')
options=('!strip' '!debug')
source=('vendor.rpm::@URL@')
noextract=('vendor.rpm')
sha256sums=('@SHA256@')
package() {
  bsdtar --no-same-owner -xf vendor.rpm -C "$pkgdir"
  install -Dm644 "$startdir/hqplayerd.service" "$pkgdir/usr/lib/systemd/system/hqplayerd.service"
  install -Dm644 "$startdir/hqplayerd-user.service" "$pkgdir/usr/lib/systemd/user/hqplayerd.service"
  install -Dm644 "$pkgdir/usr/share/doc/hqplayerd/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  # Register the private vendor library directory. Older local installs made
  # unowned /usr/lib symlinks; adopting those paths would make pacman reject an upgrade.
  install -dm755 "$pkgdir/etc/ld.so.conf.d" "$pkgdir/opt/hqplayerd/lib"
  printf '%s\n' /opt/hqplayerd/lib >"$pkgdir/etc/ld.so.conf.d/hqplayer-embedded.conf"
  if [[ ! -e $pkgdir/opt/hqplayerd/lib/libomp.so.5 ]]; then
    ln -s /usr/lib/libomp.so "$pkgdir/opt/hqplayerd/lib/libomp.so.5"
  fi
}
