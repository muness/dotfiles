#!/usr/bin/python3
"""Update the local Omarchy desktop from the newest upstream release (including RCs)."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

REPOSITORY = 'https://github.com/omacom/omarchy.git'
RELEASES = 'https://api.github.com/repos/omacom/omarchy/releases?per_page=100'
RECIPE = Path(__file__).resolve().parent


def output(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def latest_release(releases):
    candidates = [r for r in releases if not r.get('draft')
                  and re.fullmatch(r'v\d+\.\d+\.\d+(?:-rc\d+)?', r.get('tag_name', ''))]
    if not candidates:
        raise ValueError('No upstream release found')
    # Version order keeps a later RC from being replaced by a newly published
    # maintenance release on an older series. Final releases follow their RCs.
    def version(release):
        core, _, rc = release['tag_name'][1:].partition('-rc')
        return (*map(int, core.split('.')), not bool(rc), int(rc or 0))
    return max(candidates, key=version)['tag_name']


def recipe_digest():
    digest = hashlib.sha256()
    for path in sorted(RECIPE.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
            digest.update(str(path.relative_to(RECIPE)).encode() + b'\0' + path.read_bytes())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    releases = json.loads(output('curl', '-fsSL', '--retry', '3', '--max-time', '30', RELEASES))
    tag = latest_release(releases)
    version = tag.removeprefix('v').replace('-rc', 'rc')
    runtime = Path('/usr/share/omarchy')
    installed_tag = (runtime / 'desktop-upstream-release')
    installed_recipe = runtime / 'desktop-package-digest'
    current = (installed_tag.exists() and installed_tag.read_text().strip() == tag
               and installed_recipe.exists() and installed_recipe.read_text().strip() == recipe_digest())
    print(f'Omarchy: upstream {tag}; installed ' +
          ((runtime / 'version').read_text().strip() if (runtime / 'version').exists() else 'none'), flush=True)
    if args.check:
        print('Omarchy desktop is current.' if current else f'Omarchy desktop would update to {tag}.')
        return
    if os.geteuid() == 0:
        raise SystemExit('Run as your desktop user; only pacman installation needs authentication.')
    cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'dotfiles/omarchy-desktop'
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / 'update.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if current and not args.force:
            if not args.build_only:
                subprocess.run(['pkexec', '/usr/bin/pacman', '-Syu', '--disable-download-timeout'], check=True)
            return
        source = cache / 'releases' / tag
        if not (source / '.git').is_dir():
            source.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['git', 'clone', '--depth', '1', '--branch', tag, REPOSITORY, str(source)], check=True)
        if output('git', '-C', str(source), 'status', '--porcelain'):
            raise SystemExit('Release checkout has local changes: ' + str(source))
        if output('git', '-C', str(source), 'rev-parse', 'HEAD') != output('git', '-C', str(source), 'rev-parse', tag + '^{commit}'):
            raise SystemExit('Release checkout does not match ' + tag)
        build = cache / 'builds' / tag
        build.mkdir(parents=True, exist_ok=True)
        (build / 'PKGBUILD').write_bytes((RECIPE / 'PKGBUILD').read_bytes())
        env = dict(os.environ, OMARCHY_DESKTOP_RECIPE=str(RECIPE),
                   OMARCHY_DESKTOP_SOURCE=str(source), OMARCHY_DESKTOP_VERSION=version,
                   OMARCHY_DESKTOP_RELEASE=tag, OMARCHY_DESKTOP_RECIPE_DIGEST=recipe_digest())
        subprocess.run(['makepkg', '--nodeps', '--force', '--noconfirm'], cwd=build, env=env, check=True)
        archives = output('makepkg', '--packagelist', cwd=build, env=env).splitlines()
        if len(archives) != 1 or not Path(archives[0]).is_file():
            raise SystemExit('Expected exactly one desktop package')
        print('Built: ' + archives[0], flush=True)
        if args.build_only:
            return
        subprocess.run(['pkexec', '/usr/bin/python3', str(RECIPE / 'install-host.py'), archives[0]], check=True)
        print('Omarchy updated. Log out and back in to load the new desktop. Your personal configuration was preserved.')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
