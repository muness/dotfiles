#!/bin/bash
# Foyer's disposable Chromium window, with its loopback proxy excluded from
# Chrome's DNS-blocking rule (Chrome 157 otherwise cannot reach the proxy).
set -euo pipefail
browser=""
for candidate in google-chrome google-chrome-stable chromium chromium-browser brave-browser brave microsoft-edge; do
  if command -v "$candidate" >/dev/null 2>&1; then
    browser=$candidate
    break
  fi
done
[[ -n $browser ]] || { echo 'Wi-Fi sign-in needs a Chromium-family browser' >&2; exit 1; }
profile=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-portal-profile.XXXXXXXX")
trap 'rm -rf -- "$profile"' EXIT
"$browser" --user-data-dir="$profile" \
  --proxy-server="socks5://${PROXY:?Foyer proxy address missing}" \
  --host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1" \
  --disable-features=HttpsUpgrades,HttpsFirstModeIncognito \
  --no-first-run --no-default-browser-check --new-window --incognito "${1:?Sign-in URL missing}"
