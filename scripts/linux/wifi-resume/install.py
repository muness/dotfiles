#!/usr/bin/python3
"""Install/remove the root-owned, hardware-gated Wi-Fi recovery service."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

SOURCE = Path(__file__).resolve().parent
HELPER = Path('/usr/local/libexec/dotfiles-wifi-resume')
UNIT = Path('/etc/systemd/system/dotfiles-wifi-resume.service')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--remove', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('Run this installer with pkexec /usr/bin/python3.')
    if args.remove:
        subprocess.run(['/usr/bin/systemctl', 'disable', '--now', UNIT.name], check=True)
        UNIT.unlink(missing_ok=True)
        HELPER.unlink(missing_ok=True)
    else:
        HELPER.parent.mkdir(parents=True, exist_ok=True)
        for source, target, mode in [('recover.py', HELPER, 0o755),
                                     (UNIT.name, UNIT, 0o644)]:
            shutil.copyfile(SOURCE / source, target)
            os.chown(target, 0, 0)
            target.chmod(mode)
        subprocess.run(['/usr/bin/systemd-analyze', 'verify', str(UNIT)], check=True)
    subprocess.run(['/usr/bin/systemctl', 'daemon-reload'], check=True)
    if not args.remove:
        subprocess.run(['/usr/bin/systemctl', 'enable', UNIT.name], check=True)
    print('Removed Wi-Fi recovery.' if args.remove else 'Enabled automatic Wi-Fi recovery after resume.')


if __name__ == '__main__':
    main()
