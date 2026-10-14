#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2154  # dotfiles_dir comes from lib.sh
# Fedora / Fedora Asahi Remix packages and desktop. Sourced by install-linux.sh.
# Set SKIP_DESKTOP=1 for a headless host (no COSMIC, flatpaks, or GUI apps).
# shellcheck source=common.sh
source "$dotfiles_dir/scripts/linux/common.sh"

# The portable CLI set (fzf, fd, bat, rg, zoxide, direnv, atuin, starship, gh,
# jq, uv, sccache, shellcheck, shfmt, gitleaks, terraform, typst, d2, marksman,
# cloudflared, coder, java) comes from mise, not dnf.
dnf_packages=(
  # Shell and dotfiles plumbing
  zsh zsh-autosuggestions zsh-syntax-highlighting stow git git-lfs curl wget
  # Development
  gcc gcc-c++ clang make cmake ninja-build automake pkgconf-pkg-config openssl-devel
  protobuf-compiler zig bats ansible
  # Java comes from mise; Fedora 44 has no java-17/21 -devel packages.
  # Docs and media
  pandoc vips-tools espeak-ng whisper-cpp
  # Network and services
  caddy iperf3 lftp tailscale
  # Hardware, disks, images
  smartmontools dfu-util qemu-system-aarch64 squashfs-tools xorriso android-tools ollama
  # Containers
  podman distrobox
)

desktop_packages=(flatpak keepassxc syncthing chromium vlc 1password-cli openssh-askpass
  # Screenshots: cosmic-screenshot captures, Satty annotates (see install_satty).
  cosmic-screenshot wl-clipboard google-noto-color-emoji-fonts)
# Satty has no Fedora RPM or Flathub build and its release binary is x86-64
# only, so it is built from crates.io; these are its build dependencies.
satty_build_deps=(gtk4-devel libadwaita-devel libepoxy-devel fontconfig-devel)
flatpaks=(dev.zed.Zed md.obsidian.Obsidian dev.vencord.Vesktop)

add_repos() {
  dnf config-manager --help >/dev/null 2>&1 || sudo dnf install -y dnf5-plugins
  [[ -f /etc/yum.repos.d/mise.repo ]] ||
    sudo dnf config-manager addrepo --from-repofile=https://mise.jdx.dev/rpm/mise.repo
  [[ -f /etc/yum.repos.d/tailscale.repo ]] ||
    sudo dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  if [[ ! -f /etc/yum.repos.d/1password.repo ]]; then
    sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
    sudo tee /etc/yum.repos.d/1password.repo >/dev/null <<'REPO'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
REPO
  fi
}

install_system_packages() {
  add_repos
  # Package availability differs between Fedora releases and architectures;
  # report what was skipped rather than failing the whole install.
  sudo dnf install -y --skip-unavailable mise "${dnf_packages[@]}"
  sudo systemctl enable --now tailscaled || true

  [[ ${SKIP_DESKTOP:-} == 1 ]] && return
  sudo dnf install -y --skip-unavailable "${desktop_packages[@]}"

  if ! rpm -q cosmic-session >/dev/null 2>&1; then
    echo "Installing the COSMIC desktop..."
    sudo dnf install -y @cosmic-desktop-environment
  fi
  # A Minimal install has no display manager; KDE/GNOME installs keep theirs.
  if ! systemctl is-enabled display-manager.service >/dev/null 2>&1; then
    sudo systemctl enable cosmic-greeter.service
  fi
  # Always boot to the graphical target on a desktop profile. This must not sit
  # inside the check above: installing COSMIC can enable the greeter itself, so
  # the check passes and a Minimal image would keep booting to a text console.
  sudo systemctl set-default graphical.target

  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y --noninteractive flathub "${flatpaks[@]}"

  bash "$dotfiles_dir/scripts/linux/1password.sh"
  install_chatgpt
  install_chrome
  systemctl --user enable --now syncthing.service || true
}

# swamp ships no aarch64 Linux release; build it once rustup exists.
install_swamp() {
  command -v swamp >/dev/null 2>&1 && return
  cargo install --locked --git https://github.com/open-horizon-labs/swamp swamp
}

# Wayland screenshot annotator; pairs with cosmic-screenshot. Desktop only.
install_satty() {
  [[ ${SKIP_DESKTOP:-} == 1 ]] && return
  command -v satty >/dev/null 2>&1 && return
  sudo dnf install -y --skip-unavailable "${satty_build_deps[@]}"
  cargo install --locked satty
}

# OpenAI's official ChatGPT desktop app (Linux preview; Fedora 43/44, x86_64 and
# aarch64). The RPM is ~500 MB and installs /etc/yum.repos.d/chatgpt.repo with a
# signed repo, so later updates come through dnf. The first install is trusted
# on the HTTPS download alone because the signing key ships inside the package.
install_chatgpt() {
  rpm -q chatgpt >/dev/null 2>&1 && return
  local rpm_file
  rpm_file=$(mktemp --suffix=.rpm)
  curl -fSL "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.$(uname -m).rpm" -o "$rpm_file" &&
    sudo dnf install -y "$rpm_file" || echo "warning: ChatGPT desktop app not installed" >&2
  rm -f "$rpm_file"
}

# Google ships official Chrome for Linux arm64 (since July 2026). The RPM adds
# Google's yum repo, so later updates come through dnf. Chromium stays installed.
install_chrome() {
  rpm -q google-chrome-stable >/dev/null 2>&1 && return
  local arch
  arch=$(uname -m)
  sudo dnf install -y "https://dl.google.com/linux/direct/google-chrome-stable_current_${arch}.rpm" ||
    echo "warning: Google Chrome not installed" >&2
}
