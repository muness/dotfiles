#!/usr/bin/env bash
# Fresh Arch ARM workstation with the complete Aurora stack.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$here/install.sh" --profile asahi --aurora "$@"
