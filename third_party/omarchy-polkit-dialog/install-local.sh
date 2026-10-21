#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
target="$config/plugins/muness.polkit"
[[ ! -e "$target" ]] || { echo "Clone exists; review changes before updating: $target" >&2; exit 1; }
cp -p "$config/shell.json" "$config/shell.json.before-polkit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$target"
for name in PolkitAgent.qml PolkitModel.js manifest.json LICENSE; do cp "$root/$name" "$target/$name"; done
omarchy-shell shell rescanPlugins
# Discovery is asynchronous. Wait for this exact plugin before enabling it.
for (( attempt=0; attempt<30; attempt++ )); do
  if omarchy-shell shell listPlugins | jq -e 'any(.[]; .id == "muness.polkit")' >/dev/null; then break; fi
  sleep 0.1
done
omarchy-shell shell enablePlugin muness.polkit '{}'
omarchy-restart-shell
