#!/usr/bin/env bash
# Fedora backend for vendor-apps.sh. Installed RPMs add their vendor repositories.
set -euo pipefail
mode=install
apps=()
for option in "$@"; do
  case $option in
    --check|--dry-run) mode=check ;;
    --download-only) mode=download ;;
    --build-only) echo 'Fedora uses vendor RPMs; use --download-only.' >&2; exit 2 ;;
    --force) ;;
    chatgpt|chrome) apps+=("$option") ;;
    *) echo "Unsupported Fedora vendor app: $option" >&2; exit 2 ;;
  esac
done
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for app in "${apps[@]}"; do
  case $app in
    chatgpt)
      package=chatgpt
      url="https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.$(uname -m).rpm" ;;
    chrome)
      package=google-chrome-stable
      url="https://dl.google.com/linux/direct/google-chrome-stable_current_$(uname -m).rpm" ;;
  esac
  if [[ $mode == check ]]; then
    if rpm -q "$package"; then
      dnf check-upgrade "$package" && continue
      result=$?
      [[ $result == 100 ]] || exit "$result"
    else
      echo "$app: not installed; would install latest vendor RPM"
    fi
  elif [[ $mode == install ]] && rpm -q "$package" >/dev/null 2>&1; then
    pkexec /usr/bin/dnf upgrade -y "$package"
  else
    cache=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/vendor-apps/$app
    mkdir -p "$cache"
    curl -fSL --retry 3 "$url" -o "$tmp/$app.rpm"
    rpm -qp "$tmp/$app.rpm"
    mv "$tmp/$app.rpm" "$cache/latest.rpm"
    if [[ $mode == download ]]; then
      echo "Downloaded: $cache/latest.rpm"
    else
      pkexec /usr/bin/dnf install -y "$cache/latest.rpm"
    fi
  fi
done
