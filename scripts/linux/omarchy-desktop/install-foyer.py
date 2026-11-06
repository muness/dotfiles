#!/usr/bin/python3
"""Install the latest checksum-verified native Foyer release for this user."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import tarfile
from urllib.request import urlopen


def resolve(release, machine):
    tag = release.get('tag_name', '')
    if not re.fullmatch(r'v\d+(?:\.\d+)+', tag) or release.get('prerelease') or release.get('draft'):
        raise ValueError('Expected stable Foyer release')
    version = tag[1:]
    arch = {'aarch64': 'arm64', 'x86_64': 'amd64'}[machine]
    name = f'foyer_{version}_linux_{arch}.tar.gz'
    assets = [a for a in release.get('assets', []) if a.get('name') == name]
    if len(assets) != 1:
        raise ValueError('Expected one native Foyer asset')
    asset = assets[0]
    url = asset.get('browser_download_url', '')
    digest = asset.get('digest', '')
    if url != f'https://github.com/tektum/foyer/releases/download/{tag}/{name}' or not re.fullmatch(r'sha256:[a-fA-F0-9]{64}', digest):
        raise ValueError('Invalid Foyer release metadata')
    return version, url, digest[7:].lower()


def install(check=False, download=False, force=False):
    if os.geteuid() == 0:
        raise SystemExit('Run as the desktop user, not root')
    with urlopen('https://api.github.com/repos/tektum/foyer/releases/latest', timeout=30) as response:
        version, url, checksum = resolve(json.load(response), platform.machine())
    directory = Path.home() / '.local/libexec'
    target = directory / f'foyer-{version}'
    link = directory / 'foyer'
    current = target.is_file() and link.is_symlink() and link.resolve() == target
    if check:
        print(f'foyer: current (upstream {version})' if current and not force else f'foyer: would update to {version}')
        return target
    directory.mkdir(parents=True, exist_ok=True)
    if not target.exists() or force:
        with urlopen(url, timeout=30) as response:
            archive = response.read()
        if hashlib.sha256(archive).hexdigest() != checksum:
            raise SystemExit('Foyer release checksum mismatch; nothing installed')
        if download:
            cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'dotfiles/vendor-apps/foyer'
            cache.mkdir(parents=True, exist_ok=True)
            archive_path = cache / url.rsplit('/', 1)[1]
            archive_path.write_bytes(archive)
            print(f'Downloaded and verified: {archive_path}')
            return target
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
            binary = tar.extractfile('foyer').read()
        temporary = target.with_suffix('.new')
        temporary.write_bytes(binary)
        temporary.chmod(0o755)
        temporary.replace(target)
    if not download:
        temporary = directory / '.foyer-link.new'
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(target.name)
        temporary.replace(link)
    print(f'Foyer {version}: {target}')
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', '--dry-run', action='store_true')
    parser.add_argument('--download-only', '--build-only', action='store_true')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    install(args.check, args.download_only, args.force)
