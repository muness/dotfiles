#!/usr/bin/env python3
"""Update the native Asahi Wine/FEX package set from its existing publisher."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

REPO = 'lacamar/wine-arm64ec-rpm'
BASE = f'https://github.com/{REPO}/releases/download/arch-repo/'
PACKAGES = ('fex-emu-wine', 'wine', 'wine-mono', 'wine-gecko', 'wine-dxvk',
            'wine-dxvk-d3d10', 'wine-dxvk-d3d8', 'wine-dxvk-d3d9', 'wine-dxvk-dxgi',
            'wine-vkd3d-proton', 'wine-d7vk')


def candidates(release):
    if release.get('tag_name') != 'arch-repo' or release.get('draft'):
        raise ValueError('Expected publisher Arch repository release')
    result = {}
    for asset in release.get('assets', []):
        name = asset.get('name', '')
        match = re.fullmatch(r'([a-z0-9+_.-]+)-([0-9][a-zA-Z0-9.+_~:]*)-([0-9]+)-(aarch64|any)\.pkg\.tar\.(?:xz|zst)', name)
        if not match:
            continue
        package, version, revision, _ = match.groups()
        if package.removesuffix('-git') not in PACKAGES:
            continue
        url = asset.get('browser_download_url', '')
        digest = asset.get('digest', '')
        if url != BASE + name or not re.fullmatch(r'sha256:[a-fA-F0-9]{64}', digest):
            raise ValueError('Invalid native Wine package metadata')
        if package in result:
            raise ValueError('Duplicate native Wine package')
        result[package] = dict(name=name, version=version + '-' + revision,
                               url=url, sha256=digest[7:].lower())
    return result


def installed(package):
    query = subprocess.run(['pacman', '-Q', package], text=True, capture_output=True)
    fields = query.stdout.split()
    # Pacman can resolve a provided name to its replacement package. Only an
    # exact identity counts here, or a completed -git migration looks pending.
    return fields[1] if query.returncode == 0 and len(fields) == 2 and fields[0] == package else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', '--dry-run', action='store_true')
    parser.add_argument('--download-only', '--build-only', action='store_true')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    if os.uname().machine != 'aarch64':
        raise SystemExit('This Wine/FEX feed is native aarch64 only')
    with urllib.request.urlopen(f'https://api.github.com/repos/{REPO}/releases/tags/arch-repo', timeout=30) as response:
        releases = candidates(json.load(response))
    selected = []
    for name in PACKAGES:
        old_name, old = name, installed(name)
        if not old:
            old_name, old = name + '-git', installed(name + '-git')
        if not old:
            continue
        new_name = name if name in releases else name + '-git'
        if new_name not in releases:
            raise SystemExit(f'Publisher has no update candidate for installed {old_name}')
        asset = releases[new_name]
        changed = int(subprocess.check_output(['vercmp', old, asset['version']], text=True)) < 0
        changed = changed or old_name != new_name or args.force
        print(f'wine-arm64ec: {old_name} {old}; publisher {new_name} {asset["version"]}' +
              ('; would update' if changed else '; current'), flush=True)
        if changed:
            selected.append((new_name, asset))
    if args.check or not selected:
        return
    cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'dotfiles/vendor-apps/wine-arm64ec'
    cache.mkdir(parents=True, exist_ok=True)
    archives = []
    for name, asset in selected:
        archive = cache / asset['name']
        def valid():
            if not archive.exists():
                return False
            with archive.open('rb') as stream:
                return hashlib.file_digest(stream, 'sha256').hexdigest() == asset['sha256']
        if not valid():
            temp = archive.with_suffix('.part')
            subprocess.run(['curl', '-fL', '--retry', '3', '--proto', '=https', '--proto-redir', '=https',
                            asset['url'], '-o', str(temp)], check=True)
            with temp.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != asset['sha256']:
                    raise SystemExit('Wine publisher checksum mismatch')
            temp.replace(archive)
        identity = subprocess.check_output(['pacman', '-Qp', str(archive)], text=True).split()
        if identity != [name, asset['version']]:
            raise SystemExit('Wine package identity differs from release metadata')
        archives.append(str(archive))
    if args.download_only:
        print('Downloaded and verified: ' + '\n'.join(archives))
        return
    print('Installing native Wine/FEX updates; graphical authentication may be requested.', flush=True)
    subprocess.run(['pkexec', '/usr/bin/pacman', '-Syu', '--noconfirm'], check=True)
    subprocess.run(['pkexec', '/usr/bin/pacman', '-U', *archives], check=True)


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
