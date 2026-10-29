#!/usr/bin/env python3
"""Resolve a published GitHub release asset and its advertised digest."""
import argparse
import json
import re
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('kind', choices=('tether', 'aurora'))
    parser.add_argument('--index-file')
    args = parser.parse_args()
    repo = 'zackb/tether' if args.kind == 'tether' else 'omacom/linux-aurora'
    if args.index_file:
        with open(args.index_file) as f:
            releases = json.load(f)
    else:
        data = subprocess.check_output(['curl', '-fsSL', '--retry', '3', '--max-time', '30',
                                        '--proto', '=https', '--proto-redir', '=https',
                                        f'https://api.github.com/repos/{repo}/releases?per_page=100'], text=True)
        releases = json.loads(data)
    arch = subprocess.check_output(['uname', '-m'], text=True).strip()
    matches = []
    for release in releases:
        if release.get('draft') or release.get('prerelease'):
            continue
        tag = release.get('tag_name', '')
        pattern = r'v(\d+(?:\.\d+)+)' if args.kind == 'tether' else r'aurora-(\d+(?:\.\d+)+)'
        match = re.fullmatch(pattern, tag)
        if not match:
            continue
        version = match.group(1)
        name = f'tether-{version}-{arch}.AppImage' if args.kind == 'tether' else 'install-aurora-sep.sh'
        for asset in release.get('assets', []):
            if asset.get('name') != name:
                continue
            digest = asset.get('digest') or ''
            url = asset.get('browser_download_url', '')
            if not re.fullmatch(r'sha256:[a-fA-F0-9]{64}', digest) or url != f'https://github.com/{repo}/releases/download/{tag}/{name}':
                raise ValueError('Invalid release asset metadata')
            matches.append((tuple(map(int, version.split('.'))), tag, url, digest[7:].lower()))
    if not matches:
        raise SystemExit('No compatible stable release with a SHA-256 digest found')
    _, tag, url, digest = max(matches)
    print('\t'.join((tag, url, digest)))


if __name__ == '__main__':
    main()
