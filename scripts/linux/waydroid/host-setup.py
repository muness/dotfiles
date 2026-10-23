#!/usr/bin/python3
"""Privileged final setup, after complete image downloads and Binder checks."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

if os.geteuid() != 0:
    raise SystemExit('Requires root through the Waydroid installer.')
for filename, content in [
    ('/etc/modules-load.d/waydroid.conf', 'binder_linux\n'),
    ('/etc/modprobe.d/waydroid.conf', 'options binder_linux devices=binder,hwbinder,vndbinder\n'),
]:
    path = Path(filename)
    if path.exists() and path.read_text() != content:
        raise SystemExit(f'Existing custom configuration preserved: {filename}; review it before continuing.')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)

config = Path('/var/lib/waydroid/waydroid.cfg')
if not config.exists():
    if len(sys.argv) != 2:
        raise SystemExit('Missing verified image directory.')
    destination = Path('/etc/waydroid-extra/images')
    destination.mkdir(parents=True, exist_ok=True)
    for kind in ('system', 'vendor'):
        target = destination / f'{kind}.img'
        staging = target.with_suffix('.img.new')
        shutil.copyfile(Path(sys.argv[1]) / target.name, staging)
        staging.chmod(0o644)
        staging.replace(target)
    subprocess.run(['/usr/bin/python3', '/usr/bin/waydroid', 'init'], check=True)
subprocess.run(['/usr/bin/systemctl', 'enable', '--now', 'waydroid-container.service'], check=True)
