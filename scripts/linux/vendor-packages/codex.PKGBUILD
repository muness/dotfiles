# Preserve the complete official package layout, including bundled helpers.
pkgname=openai-codex-bin
pkgver=@VERSION@
pkgrel=@REVISION@
pkgdesc='OpenAI Codex CLI (official native binary package)'
arch=('aarch64' 'x86_64')
url='https://github.com/openai/codex'
license=('Apache-2.0')
depends=('glibc' 'alsa-lib')
optdepends=('git: working with Git repositories' 'pipewire-alsa: voice audio through PipeWire')
provides=('openai-codex')
conflicts=('openai-codex' 'openai-codex-autoup-bin')
replaces=('openai-codex-autoup-bin')
options=('!strip' '!debug')
source=('vendor.tar.zst::@URL@')
noextract=('vendor.tar.zst')
sha256sums=('@SHA256@')

package() {
  install -dm755 "$pkgdir/opt/openai-codex" "$pkgdir/usr/bin"
  bsdtar --no-same-owner -xf vendor.tar.zst -C "$pkgdir/opt/openai-codex"
  local binary
  for binary in codex codex-code-mode-host codex-exec-server; do
    test -x "$pkgdir/opt/openai-codex/bin/$binary" || return 1
    ln -s "/opt/openai-codex/bin/$binary" "$pkgdir/usr/bin/$binary"
  done
  install -dm755 "$pkgdir/usr/share/bash-completion/completions" \
    "$pkgdir/usr/share/zsh/site-functions" "$pkgdir/usr/share/fish/vendor_completions.d"
  "$pkgdir/opt/openai-codex/bin/codex" completion bash > "$pkgdir/usr/share/bash-completion/completions/codex"
  "$pkgdir/opt/openai-codex/bin/codex" completion zsh > "$pkgdir/usr/share/zsh/site-functions/_codex"
  "$pkgdir/opt/openai-codex/bin/codex" completion fish > "$pkgdir/usr/share/fish/vendor_completions.d/codex.fish"
}
