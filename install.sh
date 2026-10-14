#!/usr/bin/env bash
# Entry point: pick a profile and run the installer for it.
#   mac     macOS: Brewfile, tiling stack, launch agents
#   asahi   Apple Silicon on Fedora or Arch ARM/Aurora: COSMIC, flatpaks, 1Password
#   server  headless Linux, e.g. the homelab: CLI set and services, no desktop
# Without --profile: Darwin is mac, Apple Silicon/Asahi/Aurora is asahi, other Linux is server.
set -euo pipefail
# macOS ships bash 3.2, where an empty array is "unbound" under set -u, so the
# ${args[@]+...} form below is deliberate.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

profile=${DOTFILES_PROFILE:-}
args=()
while (($#)); do
  case $1 in
    --profile) profile=${2:?--profile needs mac, asahi or server}; shift 2 ;;
    --profile=*) profile=${1#*=}; shift ;;
    *) args+=("$1"); shift ;;
  esac
done

if [[ -z $profile ]]; then
  case $(uname -s) in
    Darwin) profile=mac ;;
    Linux)
      if [[ -r /proc/device-tree/compatible ]] && grep -aq 'apple,arm-platform' /proc/device-tree/compatible; then
        profile=asahi
      else
        case $(uname -r) in *asahi*|*aurora*|*-sep-ARCH*) profile=asahi ;; *) profile=server ;; esac
      fi ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 2 ;;
  esac
fi

echo "Profile: $profile"
export DOTFILES_PROFILE=$profile
case $profile in
  mac) exec bash "$here/scripts/install-macos.sh" ${args[@]+"${args[@]}"} ;;
  asahi) exec bash "$here/scripts/install-linux.sh" ${args[@]+"${args[@]}"} ;;
  server) SKIP_DESKTOP=1 exec bash "$here/scripts/install-linux.sh" ${args[@]+"${args[@]}"} ;;
  *) echo "Unknown profile '$profile' (use mac, asahi or server)" >&2; exit 2 ;;
esac
