#!/usr/bin/python3
"""Root-owned helper: only change this MacBook's persistent 80/100% cap."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import tempfile

CONFIG = Path('/etc/tlp.d/10-macbook-charge-limit.conf')
THRESHOLD = Path('/sys/class/power_supply/macsmc-battery/charge_control_end_threshold')


def write_config(content):
    fd, name = tempfile.mkstemp(prefix='.charge-limit-', dir=CONFIG.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
            os.fchmod(stream.fileno(), 0o644)
        os.replace(name, CONFIG)
    finally:
        Path(name).unlink(missing_ok=True)


def set_limit(limit):
    if limit not in ('80', '100'):
        raise ValueError('Choose 80 or 100')
    previous = THRESHOLD.read_text().strip()
    original = CONFIG.read_text()
    lines = original.splitlines(keepends=True)
    matches = [i for i, line in enumerate(lines) if line.startswith('STOP_CHARGE_THRESH_BAT0=')]
    if len(matches) != 1:
        raise ValueError('Unexpected charge configuration; leaving it unchanged')
    lines[matches[0]] = f'STOP_CHARGE_THRESH_BAT0={limit}\n'
    write_config(''.join(lines))
    try:
        subprocess.run(['/usr/bin/tlp', 'setcharge'], check=True)
        if THRESHOLD.read_text().strip() != limit:
            raise RuntimeError('The hardware did not accept the charge limit')
    except Exception:
        write_config(original)
        # Restore the previous runtime threshold even if it differed from config.
        subprocess.run(['/usr/bin/tlp', 'setcharge', previous, previous], check=False)
        raise


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('80', '100'):
        raise SystemExit('Usage: set-charge-limit.py 80|100')
    if os.geteuid() != 0:
        raise SystemExit('Run this helper through pkexec')
    with open('/run/lock/dotfiles-battery-charge.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        set_limit(sys.argv[1])


if __name__ == '__main__':
    main()
