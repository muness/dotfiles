#!/usr/bin/env bash
# Default entry point for manually installed Linux desktop applications.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. /etc/os-release
fedora=0
[[ " ${ID:-} ${ID_LIKE:-} " != *" fedora "* ]] || fedora=1
mode=install
force=()
user_only=0
apps=()
while (($#)); do
  case $1 in
    --check|--dry-run) mode=check ;;
    --download-only) mode=download ;;
    --build-only) mode=build ;;
    --force) force=(--force) ;;
    --user-only) user_only=1 ;;
    chatgpt|chrome|claude|browseros|codex|tether|1password|zed|bazecor|hqplayer5desktop|hqplayer-embedded|hyprmoncfg|foyer|wine-arm64ec|omarchy) apps+=("$1") ;;
    --help|-h)
      echo 'Usage: vendor-apps.sh [--check|--dry-run|--download-only|--build-only] [--force] [--user-only] [APP ...]'
      echo 'Default: ChatGPT, Chrome, Tether, 1Password and Zed; Arch also includes Claude, Codex and BrowserOS on ARM64.'
      echo '--check compares installed and available builds without changing the installation.'
      echo '--user-only updates installed Tether/Zed apps without authentication (for scheduled runs).'
      echo 'APP: chatgpt chrome claude browseros codex tether 1password zed bazecor hqplayer5desktop hqplayer-embedded hyprmoncfg foyer wine-arm64ec omarchy'
      echo 'Installed Bazecor, HQPlayer Desktop 5/Embedded and Hyprmoncfg are included automatically on Arch.'
      exit 0 ;;
    *) echo "Unknown vendor-app option: $1" >&2; exit 2 ;;
  esac
  shift
done
if ((user_only)); then
  ((${#apps[@]} == 0)) || { echo '--user-only cannot be combined with named apps.' >&2; exit 2; }
  [[ ! -f $HOME/.local/share/applications/tether.desktop ]] || apps+=(tether)
  [[ ! -x $HOME/.local/zed.app/bin/zed ]] || apps+=(zed)
  if compgen -G "$HOME/.local/libexec/foyer*" >/dev/null; then apps+=(foyer); fi
else
  ((${#apps[@]})) || {
    apps=(chatgpt chrome tether 1password zed)
    if (( ! fedora )); then
      apps+=(claude codex)
      [[ $(uname -m) != aarch64 ]] || apps+=(browseros)
      [[ ! -f /usr/share/omarchy/desktop-source-revision ]] || apps+=(omarchy)
      if compgen -G "$HOME/.local/libexec/foyer*" >/dev/null; then apps+=(foyer); fi
      # Specialized apps join the default update path when installed. A new
      # workstation does not need audio licenses or a Dygma keyboard.
      if pacman -Q fex-emu-wine >/dev/null 2>&1 || pacman -Q fex-emu-wine-git >/dev/null 2>&1; then
        apps+=(wine-arm64ec)
      fi
      for optional in bazecor hqplayer5desktop hqplayer-embedded hyprmoncfg; do
        package=$optional
        [[ $optional != hyprmoncfg ]] || package=hyprmoncfg-bin
        if pacman -Q "$package" >/dev/null 2>&1; then apps+=("$optional"); fi
      done
    fi
  }
fi
options=()
case $mode in
  check) options=(--check) ;;
  download) options=(--download-only) ;;
  build) options=(--build-only) ;;
esac
packaged=()
native=()
for app in "${apps[@]}"; do
  case $app in
    tether|1password|zed|bazecor|foyer|wine-arm64ec|omarchy) native+=("$app") ;;
    *) packaged+=("$app") ;;
  esac
done
status=0
run_backend() {
  local result
  if bash "$@"; then return 0; else result=$?; fi
  # This function must preserve pkexec cancellation instead of presenting a
  # second authentication prompt for another app in the same invocation.
  [[ $result != 126 ]] || exit 126
  status=1
}
# Run independent installers even when another app's feed or download fails.
if ((${#packaged[@]})); then
  if ((fedora)); then
    run_backend "$here/vendor-rpm-apps.sh" "${options[@]}" "${force[@]}" "${packaged[@]}"
  else
    run_backend "$here/vendor-packaged-apps.sh" "${options[@]}" "${force[@]}" "${packaged[@]}"
  fi
fi
for app in "${native[@]}"; do
  run_backend "$here/$app.sh" "${options[@]}" "${force[@]}"
done
exit "$status"
