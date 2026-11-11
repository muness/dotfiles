#!/usr/bin/python3
"""Install the local desktop package and standard repository dependencies."""
import datetime
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import shutil


def run(*args):
    subprocess.run(args, check=True)


def output(*args):
    return subprocess.check_output(args, text=True)


def install_targets(dependencies):
    # An explicit repository target bypasses an installed provider. Aurora's
    # fprintd replacement supplies this dependency but conflicts with fprintd.
    if 'fprintd' in dependencies:
        result = subprocess.run(['/usr/bin/pacman', '-T', 'fprintd'],
                                stdout=subprocess.DEVNULL, check=False)
        if result.returncode == 0:
            return [dependency for dependency in dependencies if dependency != 'fprintd']
        if result.returncode != 127:
            raise subprocess.CalledProcessError(result.returncode, result.args)
    return dependencies


def main(archive):
    if os.geteuid() != 0:
        raise SystemExit('Run with pkexec /usr/bin/python3 ' + str(Path(__file__).resolve()) + ' PACKAGE')
    archive = Path(archive).resolve(strict=True)
    if output('/usr/bin/pacman', '-Qp', str(archive)).split()[0] != 'omarchy-desktop-cosmic':
        raise SystemExit('Unexpected desktop package')
    config = Path('/etc/pacman.conf').read_bytes()
    pins = [line for line in config.splitlines() if line.startswith(b'IgnorePkg')]
    packages = ('linux-aurora', 'linux-aurora-headers', 'm1n1-aurora', 'libfprint')
    before = output('/usr/bin/pacman', '-Q', *packages)
    initramfs = Path('/boot/initramfs-linux-aurora.img')
    image_before = hashlib.sha256(initramfs.read_bytes()).hexdigest()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    snapshot = Path('/var/lib/dotfiles/snapshots') / ('pre-omarchy-desktop-' + stamp)
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    run('/usr/bin/btrfs', 'subvolume', 'snapshot', '-r', '/', str(snapshot))
    print('Root recovery snapshot:', snapshot, flush=True)
    metadata = output('/usr/bin/bsdtar', '-xOf', str(archive), '.PKGINFO')
    dependencies = [line.removeprefix('depend = ') for line in metadata.splitlines()
                    if line.startswith('depend = ')]
    run('/usr/bin/pacman', '-Syu', '--disable-download-timeout', '--needed', '--noconfirm', *install_targets(dependencies))
    assert output('/usr/bin/pacman', '-Q', *packages) == before, 'Aurora stack changed unexpectedly'
    assert [line for line in Path('/etc/pacman.conf').read_bytes().splitlines() if line.startswith(b'IgnorePkg')] == pins
    run('/usr/bin/pacman', '-U', '--noconfirm', str(archive))
    for name in ('omarchy-lock-password', 'omarchy-lock-fingerprint'):
        target = Path('/etc/pam.d') / name
        if target.exists():
            print('Preserving existing PAM service:', target)
        else:
            shutil.copyfile(Path('/usr/share/omarchy/pam') / name, target)
            target.chmod(0o644)
            print('Created PAM service:', target)
    assert Path('/etc/pacman.conf').read_bytes() == config, 'Pacman configuration changed'
    assert hashlib.sha256(initramfs.read_bytes()).hexdigest() == image_before, 'Boot image changed during desktop install'
    listing = output('/usr/bin/lsinitcpio', str(initramfs))
    for driver in ('hid-apple.ko', 'hid-magicmouse.ko'):
        assert driver in listing, 'Missing early input module: ' + driver
    print('Verified both Apple HID modules in initramfs; Aurora pins and boot image preserved.')
    run('/usr/bin/systemctl', 'is-active', 'cosmic-greeter', 'earlyoom', 'dev-zram0.swap')
    print(output('/usr/bin/swapon', '--show'))


if __name__ == '__main__':
    main(*sys.argv[1:])
