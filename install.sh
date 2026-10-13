#!/usr/bin/env bash
# Entry point: dispatch to the installer for this OS.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

case $(uname -s) in
  Darwin) exec bash "$here/scripts/install-macos.sh" "$@" ;;
  Linux)  exec bash "$here/scripts/install-linux.sh" "$@" ;;
  *) echo "Unsupported OS: $(uname -s)" >&2; exit 2 ;;
esac
