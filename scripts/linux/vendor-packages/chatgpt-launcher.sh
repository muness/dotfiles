#!/usr/bin/env bash
# Native Wayland on COSMIC; command-line flags can select another platform.
set -euo pipefail
flags=()
flags_file=${XDG_CONFIG_HOME:-$HOME/.config}/chatgpt-flags.conf
if [[ -r $flags_file ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    read -r -a words <<<"$line"
    flags+=("${words[@]}")
  done <"$flags_file"
fi
platform=()
if [[ -n ${WAYLAND_DISPLAY:-} || ${XDG_SESSION_TYPE:-} == wayland ]]; then
  platform=(--ozone-platform=wayland)
  for flag in "${flags[@]}" "$@"; do
    case $flag in --ozone-platform=*|--ozone-platform-hint=*) platform=() ;; esac
  done
fi
exec /usr/lib/chatgpt/ChatGPT "${platform[@]}" "${flags[@]}" "$@"
