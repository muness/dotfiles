#!/usr/bin/env bash
# Route the installed desktop's own updater through the common app entry point.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
options=()
for option in "$@"; do
  case $option in
    --check|--dry-run) options+=(--check) ;;
    --build-only|--force) options+=("$option") ;;
    --download-only) echo 'Omarchy supports --build-only rather than --download-only.' >&2; exit 2 ;;
    *) echo "Unknown Omarchy option: $option" >&2; exit 2 ;;
  esac
done
exec /usr/bin/python3 "$here/omarchy-desktop/update.py" "${options[@]}"
