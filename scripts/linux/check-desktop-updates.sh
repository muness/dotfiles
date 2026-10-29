#!/usr/bin/env bash
# Check the local vendor packages and the reviewed hardware/desktop source pins.
set -u
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
status=0
echo 'Vendor packages (dry run; full system upgrade is not simulated):'
bash "$here/vendor-apps.sh" --check || status=1
python3 "$here/github-release-metadata.py" tether || status=1
bash "$here/aurora.sh" --check || status=1
reviewed=$(sed -n "s/^REVISION = '\([0-9a-f]*\)'/\1/p" "$here/omarchy-desktop/prepare.py")
remote=$(git ls-remote https://github.com/omacom/omarchy-mac.git refs/heads/quattro) || status=1
remote=${remote%%$'\t'*}
if [[ $reviewed =~ ^[0-9a-f]{40}$ && $remote =~ ^[0-9a-f]{40}$ ]]; then
  echo "Omarchy Mac: reviewed $reviewed; upstream quattro $remote"
  [[ $reviewed == "$remote" ]] || echo 'New Omarchy desktop source requires review and a rebuild.'
else
  echo 'Could not compare Omarchy Mac revisions.' >&2
  status=1
fi
binder_base=$(sed -n 's/^_commit=\([0-9a-f]*\)$/\1/p' "$here/waydroid/PKGBUILD")
# Backticks are literal Markdown delimiters in the vendored README.
# shellcheck disable=SC2016
caffeine_base=$(sed -n 's/.*tracks upstream commit `\([0-9a-f]*\)`.*/\1/p' "$here/../../third_party/caffeine-applet/README.md")
for item in "binder|https://github.com/choff/anbox-modules.git|$binder_base" \
            "caffeine|https://github.com/codevardhan/caffeine-applet.git|$caffeine_base"; do
  IFS='|' read -r name url reviewed <<<"$item"
  [[ $reviewed =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid $name source revision." >&2; status=1; continue; }
  remote=$(git ls-remote "$url" HEAD) || { status=1; continue; }
  remote=${remote%%$'\t'*}
  [[ $remote =~ ^[0-9a-f]{40}$ ]] || { status=1; continue; }
  echo "$name: reviewed base $reviewed; upstream HEAD $remote"
  [[ $reviewed == "$remote" ]] || echo "$name has upstream changes; review local patches and compatibility."
done
exit "$status"
