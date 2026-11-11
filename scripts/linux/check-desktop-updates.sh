#!/usr/bin/env bash
# Check the local vendor packages and the reviewed hardware/desktop source pins.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
status=0
echo 'Vendor packages (dry run; full system upgrade is not simulated):'
bash "$here/vendor-apps.sh" --check || status=1
bash "$here/aurora.sh" --check || status=1
binder_base=$(sed -n 's/^_commit=\([0-9a-f]*\)$/\1/p' "$here/waydroid/PKGBUILD")
# shellcheck disable=SC2066 # Keep a list-shaped source audit for additional modules.
for item in "binder|https://github.com/choff/anbox-modules.git|$binder_base"; do
  IFS='|' read -r name url reviewed <<<"$item"
  [[ $reviewed =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid $name source revision." >&2; status=1; continue; }
  remote=$(git ls-remote "$url" HEAD) || { status=1; continue; }
  remote=${remote%%$'\t'*}
  [[ $remote =~ ^[0-9a-f]{40}$ ]] || { status=1; continue; }
  echo "$name: reviewed base $reviewed; upstream HEAD $remote"
  [[ $reviewed == "$remote" ]] || echo "$name has upstream changes; review local patches and compatibility."
done
exit "$status"
