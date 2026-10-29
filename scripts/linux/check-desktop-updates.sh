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
for item in 'binder|https://github.com/choff/anbox-modules.git|3f65f66a87b2323e56bd0d68993524d034d8b720' \
            'caffeine|https://github.com/codevardhan/caffeine-applet.git|18d59ee4d62eca1bc63f0513e05992fbb9e6f041'; do
  IFS='|' read -r name url reviewed <<<"$item"
  remote=$(git ls-remote "$url" HEAD) || { status=1; continue; }
  remote=${remote%%$'\t'*}
  [[ $remote =~ ^[0-9a-f]{40}$ ]] || { status=1; continue; }
  echo "$name: reviewed base $reviewed; upstream HEAD $remote"
  [[ $reviewed == "$remote" ]] || echo "$name has upstream changes; review local patches and compatibility."
done
exit "$status"
