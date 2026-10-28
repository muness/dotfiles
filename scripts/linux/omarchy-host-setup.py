#!/usr/bin/python3
"""Apply the reviewed host changes; run with pkexec, never the upstream installer."""
import datetime
import os
from pathlib import Path
import shutil
import subprocess


def run(*args):
    subprocess.run(args, check=True)


def fingerprint_login(original):
    expected = 'auth       sufficient   pam_fprintd.so max-tries=3 timeout=10\n'
    if original.count(expected) == 1:
        return original
    if 'pam_fprintd.so' in original:
        raise ValueError('Login already has fingerprint configuration; review before changing it')
    anchor = 'auth       include      system-local-login'
    if original.count(anchor) != 1:
        raise ValueError('Unexpected login PAM layout; preserving it')
    return original.replace(anchor, expected + anchor)


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run with pkexec /usr/bin/python3 ' + str(Path(__file__).resolve()))
    if os.uname().machine != 'aarch64' or b'apple,' not in Path('/proc/device-tree/compatible').read_bytes():
        raise SystemExit('This setup is for the Apple Silicon Arch workstation')
    login = Path('/etc/pam.d/login')
    pam = fingerprint_login(login.read_text())
    if not Path('/usr/lib/security/pam_fprintd.so').is_file():
        raise SystemExit('Missing pam_fprintd.so')
    if not Path('/usr/lib/initcpio/install/asahi').is_file():
        raise SystemExit('Missing Asahi initramfs hook')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = Path('/var/lib/dotfiles/backups') / ('omarchy-host-' + stamp)
    backup.mkdir(parents=True, mode=0o700)
    paths = ['/etc/pam.d/login', '/etc/pam.d/cosmic-greeter',
             '/etc/mkinitcpio.conf.d/apple_hid_modules.conf',
             '/etc/tlp.d/90-omarchy-power-profiles.conf',
             '/etc/systemd/zram-generator.conf.d/50-workstation-memory.conf',
             '/boot/initramfs-linux-aurora.img', '/etc/pacman.conf']
    absent = []
    for name in paths:
        source = Path(name)
        if source.exists():
            target = backup / name.lstrip('/')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        else:
            absent.append(name)
    (backup / 'originally-absent.txt').write_text('\n'.join(absent) + '\n')
    print('Backup:', backup, flush=True)

    def install(name, content):
        target = Path(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        staging = target.with_name(target.name + '.dotfiles-new')
        staging.write_text(content)
        staging.chmod(0o644)
        staging.replace(target)

    install(str(login), pam)
    # COSMIC's in-session locker uses this service; greetd uses login.
    if not Path('/etc/pam.d/cosmic-greeter').exists():
        install('/etc/pam.d/cosmic-greeter', '#%PAM-1.0\nauth include login\naccount include login\npassword include login\nsession include login\n')
    install('/etc/mkinitcpio.conf.d/apple_hid_modules.conf', '''# Load Apple input drivers before logind and the desktop enumerate devices.
for _apple_hid_module in hid_apple hid_magicmouse; do
  if modinfo -k "${KERNELVERSION:-$(uname -r)}" "$_apple_hid_module" >/dev/null 2>&1; then
    MODULES+=("$_apple_hid_module")
  fi
done
unset _apple_hid_module
''')
    install('/etc/tlp.d/90-omarchy-power-profiles.conf', '''# Keep the existing Asahi tuning; change only automatic profile selection.
TLP_AUTO_SWITCH=1
TLP_PROFILE_AC=PRF
TLP_PROFILE_BAT=BAL
''')
    install('/etc/systemd/zram-generator.conf.d/50-workstation-memory.conf', '''[zram0]
# Capacity, not a reservation: compressed pages consume RAM on demand.
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
''')
    run('/usr/bin/mkinitcpio', '-p', 'linux-aurora')
    # Reload profile defaults without replacing TLP or changing kernel governors.
    run('/usr/bin/tlp', 'start')
    run('/usr/bin/systemctl', 'restart', 'tlp-pd.service')
    run('/usr/bin/systemctl', 'daemon-reload')
    # Do not tear down live swap. A device reset can race udev/systemd;
    # configuring the next boot is safe even while memory is under pressure.
    print('Zram configuration written; a changed capacity takes effect at next boot.')
    assert Path('/etc/pacman.conf').read_bytes() == (backup / 'etc/pacman.conf').read_bytes()
    print('Host changes applied. HID fix takes effect at next boot; no reboot was requested.')


if __name__ == '__main__':
    main()
