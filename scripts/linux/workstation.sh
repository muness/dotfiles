#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2154
# Workstation helpers shared by Fedora and Arch ARM. Sourced by distro backends.
desktop_flatpaks=(md.obsidian.Obsidian dev.vencord.Vesktop)
caffeine_applet_id=com.github.codevardhan.caffeine-applet

configure_tailscale_tray() {
  command -v tailscale >/dev/null 2>&1 || return 0
  if tailscale configure systray --enable-startup=systemd; then
    systemctl --user daemon-reload
    systemctl --user enable --now tailscale-systray.service ||
      echo 'warning: enable tailscale-systray.service after logging into COSMIC' >&2
  else
    echo 'warning: could not configure the Tailscale tray startup' >&2
  fi
}

install_desktop_flatpaks() {
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y --noninteractive flathub "${desktop_flatpaks[@]}"
  install_zed
  install_vicinae
}

# Zed's official stable build installs and updates in the user's account.
install_zed() {
  if ! command -v zed >/dev/null 2>&1; then
    (
      local installer
      installer=$(mktemp)
      trap 'rm -f "$installer"' EXIT
      curl -fsSL https://zed.dev/install.sh -o "$installer"
      sh "$installer"
    )
  fi
}

# Install Vicinae's native Linux build for the current architecture, then keep
# its launcher daemon running for keyboard activation. Upstream supports x86_64
# and aarch64 AppImages and can install without root under ~/.local.
install_vicinae() {
  if ! command -v vicinae >/dev/null 2>&1; then
    (
      local installer
      installer=$(mktemp)
      trap 'rm -f "$installer"' EXIT
      curl -fsSL https://vicinae.com/install -o "$installer"
      bash "$installer" --prefix "$HOME/.local"
    )
  fi

  systemctl --user daemon-reload
  systemctl --user enable --now vicinae.service ||
    echo 'warning: enable vicinae.service after logging into the desktop session' >&2
}

# Build the customized COSMIC Caffeine applet and add it to the panel's right
# wing. Keep the upstream app ID so existing panel settings continue to work.
install_caffeine_applet() (
  set -euo pipefail
  [[ ${SKIP_DESKTOP:-} == 1 ]] && return 0
  local applet_dir="$dotfiles_dir/third_party/caffeine-applet"
  local applet_bin="$HOME/.local/bin/caffeine-applet"
  local applications_dir="$HOME/.local/share/applications"
  local icons_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
  local desktop_file="$applications_dir/$caffeine_applet_id.desktop"

  cargo build --manifest-path "$applet_dir/Cargo.toml" --release --locked
  install -Dm0755 "$applet_dir/target/release/caffeine-applet" "$applet_bin.new"
  mv -- "$applet_bin.new" "$applet_bin"
  mkdir -p "$applications_dir" "$icons_dir"
  python3 - "$applet_dir/resources/app.desktop" "$desktop_file" "$applet_bin" <<'PY'
from pathlib import Path
import re
import sys

source, target, executable = map(Path, sys.argv[1:])
desktop = source.read_text()
quoted_exec = '"' + str(executable).replace("\\", "\\\\").replace('"', '\\"') + '"'
desktop, count = re.subn(r"(?m)^Exec=.*$", f"Exec={quoted_exec}", desktop, count=1)
if count != 1:
    raise SystemExit("Could not set the Caffeine applet command")
target.write_text(desktop)
PY
  install -Dm0644 "$applet_dir/resources/icons/hicolor/scalable/apps/icon.svg" \
    "$icons_dir/$caffeine_applet_id.svg"
  install -Dm0644 "$applet_dir/resources/icons/hicolor/scalable/apps/coffee-symbolic.svg" \
    "$icons_dir/$caffeine_applet_id-symbolic.svg"
  install -Dm0644 "$applet_dir/resources/icons/hicolor/scalable/apps/coffee-full.svg" \
    "$icons_dir/$caffeine_applet_id.On.svg"
  install -Dm0644 "$applet_dir/resources/icons/hicolor/scalable/apps/coffee-empty.svg" \
    "$icons_dir/$caffeine_applet_id.Off.svg"

  local panel_config="$HOME/.config/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings"
  local default_panel_config=/usr/share/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings
  mkdir -p "$(dirname "$panel_config")"
  if [[ ! -f $panel_config ]]; then
    if [[ ! -f $default_panel_config ]]; then
      echo "warning: COSMIC panel defaults not found; add Caffeine in COSMIC Settings" >&2
      return
    fi
    cp "$default_panel_config" "$panel_config"
  fi

  python3 - "$panel_config" "$caffeine_applet_id" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
applet_id = sys.argv[2]
config = path.read_text()
if applet_id not in config:
    config, count = re.subn(
        r'("com\.system76\.CosmicAppletStatusArea")',
        rf'\1, "{applet_id}"',
        config,
        count=1,
    )
    if count != 1:
        raise SystemExit("Could not find COSMIC Status Area in panel config")
    path.write_text(config)
PY
  echo "Customized Caffeine applet installed; log out and back in to refresh the COSMIC panel."
)

# swamp ships no aarch64 Linux release; build it once rustup exists.
install_swamp() {
  command -v swamp >/dev/null 2>&1 && return
  cargo install --locked --git https://github.com/open-horizon-labs/swamp swamp
}

