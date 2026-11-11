#!/usr/bin/env python3
"""Install the workstation's selected fonts for the current Linux user."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request
import zipfile

IOSEVKA_VERSION = '34.9.1'
COMFY_COMMIT = 'c57f5c48c6565d475b88b52fed2a5e036dc43860'
ROOT = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'fonts'


def download(url, destination):
    with urllib.request.urlopen(url, timeout=120) as response, open(destination, 'wb') as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)


def install_zip_family(family):
    dest = ROOT / family
    styles = ('Regular', 'Italic', 'Medium', 'MediumItalic', 'SemiBold',
              'SemiBoldItalic', 'Bold', 'BoldItalic')
    names = [f'{family}-{style}.ttf' for style in styles]
    if all((dest / name).is_file() for name in names):
        print(f'{family}: already installed', flush=True)
        return
    dest.mkdir(parents=True, exist_ok=True)
    url = (f'https://github.com/be5invis/Iosevka/releases/download/v{IOSEVKA_VERSION}/'
           f'PkgTTF-{family}-{IOSEVKA_VERSION}.zip')
    print(f'{family}: downloading v{IOSEVKA_VERSION}', flush=True)
    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / 'fonts.zip'
        download(url, archive)
        with zipfile.ZipFile(archive) as package:
            for name in names:
                if not (dest / name).exists():
                    data = package.read(name)
                    temp_file = dest / (name + '.tmp')
                    temp_file.write_bytes(data)
                    temp_file.replace(dest / name)


def install_comfy(variant, folder):
    dest = ROOT / folder
    weights = ('regular', 'medium', 'semibold', 'bold', 'light', 'semilight', 'extrabold')
    names = [f'{variant}-normal{weight}{style}.ttf' for weight in weights
             for style in ('upright', 'italic')]
    missing = [name for name in names if not (dest / name).is_file()]
    if not missing:
        print(f'{folder}: already installed', flush=True)
        return
    dest.mkdir(parents=True, exist_ok=True)
    print(f'{folder}: downloading {len(missing)} faces', flush=True)
    base = f'https://raw.githubusercontent.com/protesilaos/iosevka-comfy/{COMFY_COMMIT}/{variant}/TTF'
    def fetch(name):
        with tempfile.NamedTemporaryFile(dir=dest, delete=False) as temp:
            path = Path(temp.name)
        try:
            download(f'{base}/{name}', path)
            path.replace(dest / name)
        finally:
            path.unlink(missing_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(fetch, missing))


def main():
    install_comfy('iosevka-comfy-wide', 'IosevkaComfyWide')
    install_comfy('iosevka-comfy-wide-duo', 'IosevkaComfyWideDuo')
    install_zip_family('IosevkaAile')
    install_zip_family('IosevkaEtoile')
    subprocess.run(['fc-cache', '-f', str(ROOT)], check=True)
    print('Fonts installed. Fully quit and reopen apps to refresh their font lists.')


if __name__ == '__main__':
    main()
