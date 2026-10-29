# Repackage Anthropic's official Debian build for Arch Linux.
pkgname=claude-desktop
pkgver=@VERSION@
pkgrel=@REVISION@
pkgdesc='Official Claude Desktop app from Anthropic'
arch=('aarch64' 'x86_64')
url='https://claude.com/download'
license=('custom')
depends=(alsa-lib at-spi2-core glibc gtk3 libdrm libnotify libsecret libxcb
  libxtst nss pipewire util-linux-libs xdg-desktop-portal xdg-utils)
makedepends=(libarchive)
optdepends=('gnome-keyring: desktop credential storage'
  'qemu-system-aarch64: Cowork virtual machine on ARM'
  'qemu-system-x86: Cowork virtual machine on x86'
  'virtiofsd: Cowork filesystem sharing')
options=('!strip' '!debug')
source=('vendor.deb::@URL@' launcher.sh)
noextract=(vendor.deb)
sha256sums=('@SHA256@' '@LAUNCHER_SHA256@')

package() {
  set -o pipefail
  local payload
  payload=$(bsdtar -tf vendor.deb | grep -E '^data\.tar\.(xz|gz|zst)$')
  [[ -n $payload ]] || return 1
  bsdtar -xOf vendor.deb "$payload" | bsdtar --no-same-owner -xf - -C "$pkgdir"
  [[ -x $pkgdir/usr/lib/claude-desktop/claude-desktop ]] || return 1
  rm -f "$pkgdir/usr/bin/claude-desktop"
  install -Dm755 launcher.sh "$pkgdir/usr/bin/claude-desktop"
  install -Dm644 "$pkgdir/usr/share/doc/claude-desktop/copyright" \
    "$pkgdir/usr/share/licenses/$pkgname/copyright"
  rm -rf "$pkgdir/usr/share/lintian" "$pkgdir/usr/share/doc"
}
