#!/usr/bin/env bash
# Entry point: pick a profile and run the installer for it.
#   mac     macOS: Brewfile, tiling stack, launch agents
#   asahi   Fedora Asahi (or any Linux desktop): COSMIC, flatpaks, 1Password
#   server  headless Linux, e.g. the homelab: CLI set and services, no desktop
# Without --profile: Darwin is mac, an Asahi kernel is asahi, other Linux is server.
set -euo pipefail
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
    Linux) case $(uname -r) in *asahi*) profile=asahi ;; *) profile=server ;; esac ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 2 ;;
  esac
fi

echo "Profile: $profile"
export DOTFILES_PROFILE=$profile
case $profile in
  mac) exec bash "$here/scripts/install-macos.sh" "${args[@]}" ;;
  asahi) exec bash "$here/scripts/install-linux.sh" "${args[@]}" ;;
  server) SKIP_DESKTOP=1 exec bash "$here/scripts/install-linux.sh" "${args[@]}" ;;
  *) echo "Unknown profile '$profile' (use mac, asahi or server)" >&2; exit 2 ;;
esac
