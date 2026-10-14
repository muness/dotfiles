#!/usr/bin/env bash
# Private settings transfer: keep the archive outside this public repository.
# Run restore before logging into COSMIC, so the desktop does not overwrite it.
set -euo pipefail
mode=${1:-}
archive=${2:-}
[[ $# == 2 && ( $mode == backup || $mode == restore ) ]] || {
  echo 'Usage: cosmic-settings.sh backup|restore /absolute/path/to/settings.tar.gz' >&2
  exit 2
}
[[ $archive == /* ]] || { echo 'Use an absolute archive path.' >&2; exit 2; }
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
case $mode in
  backup)
    [[ -d $config_dir/cosmic ]] || { echo 'No COSMIC settings to back up.' >&2; exit 1; }
    [[ ! -e $archive ]] || { echo 'Archive already exists; choose a new path.' >&2; exit 1; }
    mkdir -p "$(dirname -- "$archive")"
    umask 077
    tar -czf "$archive" --exclude=cosmic/backups -C "$config_dir" cosmic
    echo "COSMIC settings saved to $archive" ;;
  restore)
    [[ -f $archive ]] || { echo 'Archive not found.' >&2; exit 1; }
    if pgrep -u "$(id -u)" -x cosmic-session >/dev/null; then
      echo 'Log out of COSMIC and restore from a console or SSH session.' >&2
      exit 1
    fi
    # Extract regular settings only. Reject paths or links outside the tree.
    python3 - "$archive" "$config_dir" <<'PY'
from pathlib import Path
import sys
import tarfile

archive, config = sys.argv[1], Path(sys.argv[2])
with tarfile.open(archive, "r:gz") as source:
    members = source.getmembers()
    if not members:
        raise SystemExit("The settings archive is empty")
    for member in members:
        path = Path(member.name)
        if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "cosmic":
            raise SystemExit(f"Unexpected settings path: {member.name}")
        if not (member.isdir() or member.isfile()):
            raise SystemExit(f"Expected regular settings, found link/device: {member.name}")
    config.mkdir(parents=True, exist_ok=True)
    settings = config / "cosmic"
    if settings.is_symlink():
        raise SystemExit("COSMIC settings directory is a symlink; resolve it before restoring")
    if settings.exists():
        from datetime import datetime, timezone
        backup = config / ("cosmic.before-restore-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
        settings.rename(backup)
        print(f"Existing settings saved to {backup}")
    source.extractall(config, members=members, filter="data")
PY
    echo 'COSMIC settings restored; log into COSMIC.' ;;
esac
