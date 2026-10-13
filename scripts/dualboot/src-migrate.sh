#!/usr/bin/env bash
# Copy source trees from the old machine into the shared /Volumes/src,
# skipping per-OS build output. Extra arguments go to rsync (e.g. --dry-run).
#
#   scripts/dualboot/src-migrate.sh old-mac.local:src/ --dry-run
#   scripts/dualboot/src-migrate.sh old-mac.local:src/
set -euo pipefail

source=${1:?usage: $0 <host:path/> [rsync args...]}
shift
dest=/Volumes/src/

rsync -aH --progress \
  --exclude target/ --exclude node_modules/ --exclude .venv/ --exclude venv/ \
  --exclude __pycache__/ --exclude .direnv/ --exclude .DS_Store \
  --exclude .pytest_cache/ --exclude .mypy_cache/ --exclude .gradle/ --exclude build/intermediates/ \
  "$@" "$source" "$dest"

echo "Copied. Rebuild dependencies per project (cargo build, pnpm install, uv sync)."
