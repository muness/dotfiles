#!/usr/bin/python3
"""Install a checksum-pinned upstream Foyer binary for this user."""
import hashlib
import io
import os
from pathlib import Path
import platform
import tarfile
from urllib.request import urlopen

VERSION = '0.1.0'
HASHES = {
    'aarch64': ('arm64', 'e4b04f6f5110e0b658148357d82111190072c0bfd7e40d7f16ebbaab25157511'),
    'x86_64': ('amd64', '1ab8c33224964fcb5b43eaa87af2f5812a9536a9fc51d46037e5702f9da6d6e2'),
}


def install():
    if os.geteuid() == 0:
        raise SystemExit('Run as the desktop user, not root')
    arch, checksum = HASHES[platform.machine()]
    target = Path.home() / '.local/libexec' / f'foyer-{VERSION}'
    url = f'https://github.com/tektum/foyer/releases/download/v{VERSION}/foyer_{VERSION}_linux_{arch}.tar.gz'
    with urlopen(url, timeout=30) as response:
        archive = response.read()
    if hashlib.sha256(archive).hexdigest() != checksum:
        raise SystemExit('Foyer release checksum mismatch; nothing installed')
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
        binary = tar.extractfile('foyer').read()
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.new')
    temporary.write_bytes(binary)
    temporary.chmod(0o755)
    temporary.replace(target)
    print(f'Installed Foyer {VERSION}: {target}')
    return target


if __name__ == '__main__':
    install()
