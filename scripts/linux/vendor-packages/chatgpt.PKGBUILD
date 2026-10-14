# Repackages OpenAI's official Debian binary. Dependency/layout reference:
# https://github.com/omacom/omarchy-pkgs/tree/master/pkgbuilds/openai-codex-desktop
pkgname=openai-codex-desktop
pkgver=@VERSION@
pkgrel=@REVISION@
pkgdesc='Official ChatGPT desktop app with Codex, from OpenAI'
arch=('aarch64' 'x86_64')
url='https://developers.openai.com/codex/app'
license=('custom')
depends=(alsa-lib at-spi2-core bash cairo dbus expat gcc-libs gdk-pixbuf2 glib2
  glibc gtk3 libcups libdrm libglvnd libnotify libusb libx11 libxcb libxcomposite
  libxdamage libxext libxfixes libxkbcommon libxrandr mesa nspr nss openssl
  pango python systemd-libs tpm2-tss vulkan-icd-loader xdg-utils xz)
makedepends=(libarchive)
optdepends=('gnome-keyring: desktop credential storage' 'git: version control integration')
provides=(chatgpt)
conflicts=(chatgpt)
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
  [[ -x $pkgdir/usr/lib/chatgpt/ChatGPT ]] || return 1
  rm -f "$pkgdir/usr/bin/chatgpt"
  install -Dm755 launcher.sh "$pkgdir/usr/bin/chatgpt"
  ln -sfn chatgpt "$pkgdir/usr/bin/codex-desktop"
  install -Dm644 "$pkgdir/usr/share/doc/chatgpt/copyright" \
    "$pkgdir/usr/share/licenses/$pkgname/copyright"
  rm -rf "$pkgdir/etc/apt" "$pkgdir/usr/share/lintian" "$pkgdir/usr/share/doc"
}
