#!/usr/bin/env python3
"""Add only the system-installed BrowserOS neo binary to 1Password's allowlist."""
import datetime
import os
from pathlib import Path
import shutil
import stat


def trust_browser(path):
    if path.is_symlink():
        raise ValueError('Refusing to replace a symlinked 1Password allowlist')
    text = path.read_text() if path.exists() else ''
    if 'browserclaw' in {line.strip() for line in text.splitlines()}:
        return None
    backup = None
    if path.exists():
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup = path.with_name(path.name + '.before-browseros-' + stamp)
        shutil.copy2(path, backup)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip('\n') + '\nbrowserclaw\n')
    path.chmod(0o644)
    return backup


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run through pkexec')
    browser = Path('/usr/lib/browserclaw/browserclaw')
    info = browser.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
        raise SystemExit('Install the root-owned BrowserOS neo package first')
    if not Path('/etc/1password').is_dir():
        raise SystemExit('Install 1Password desktop first')
    backup = trust_browser(Path('/etc/1password/custom_allowed_browsers'))
    if backup:
        print(f'Backup: {backup}')
    print('browserclaw is trusted. Restart and unlock 1Password, then reopen neo.')


if __name__ == '__main__':
    main()
