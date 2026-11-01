#!/usr/bin/python3
"""Recover Apple Silicon Broadcom Wi-Fi after a failed resume.

Adapted from the approach in omacom/omarchy-mac#255, extended to BCM4388.
Only association failures or a stuck connection attempt trigger a reload.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

PCI = Path('/sys/bus/pci/devices')
GRACE = 25
REJECT_GRACE = 3
RECONNECT = 40


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True,
                          timeout=10, env={**os.environ, 'LC_ALL': 'C',
                                          'PATH': '/usr/bin:/usr/sbin'}).stdout.strip()


def supported():
    if platform.machine() != 'aarch64':
        return False
    for device in PCI.iterdir():
        try:
            if (device.joinpath('vendor').read_text().strip() == '0x14e4'
                    and device.joinpath('device').read_text().strip()
                    in {'0x4425', '0x4433', '0x4434'}
                    and device.joinpath('driver').resolve().name == 'brcmfmac'):
                return True
        except FileNotFoundError:
            continue
    return False


def wifi():
    rows = command('/usr/bin/nmcli', '-t', '-f', 'DEVICE,TYPE', 'device').splitlines()
    return next((row.split(':')[0] for row in rows if row.endswith(':wifi')), None)


def state(interface):
    return int(command('/usr/bin/nmcli', '-g', 'GENERAL.STATE', 'device',
                       'show', interface).split()[0])


def allowed(interface):
    return (command('/usr/bin/nmcli', 'radio', 'wifi') == 'enabled'
            and command('/usr/bin/nmcli', '-g', 'GENERAL.AUTOCONNECT',
                        'device', 'show', interface) == 'yes')


def rejects(since, interface):
    log = command('/usr/bin/journalctl', '-b', '-u', 'wpa_supplicant.service',
                  '--since', since, '--no-pager', '-o', 'cat')
    return sum(f'{interface}: CTRL-EVENT-ASSOC-REJECT' in line
               and 'status_code=16' in line for line in log.splitlines())


def supplicant_attached(interface):
    service = 'fi.w1.wpa_supplicant1'
    paths = json.loads(command('/usr/bin/busctl', '--system', '--json=short',
                               'get-property', service, '/fi/w1/wpa_supplicant1',
                               service, 'Interfaces'))['data']
    for path in paths:
        name = json.loads(command('/usr/bin/busctl', '--system', '--json=short',
                                  'get-property', service, path,
                                  service + '.Interface', 'Ifname'))['data']
        if name == interface:
            return True
    return False


def restore_management():
    # Firmware loading can finish asynchronously after modprobe returns.
    for _ in range(40):
        interface = wifi()
        if interface:
            command('/usr/bin/nmcli', 'device', 'set', interface, 'managed', 'yes')
            return
        time.sleep(0.25)
    raise RuntimeError('Wi-Fi device did not return; could not restore NetworkManager management.')


def reload_driver(interface):
    # An immediate unload can race the supplicant's P2P interface creation.
    # On 2026-10-31 this triggered a NULL dereference in brcmf_fweh_p2pdev_setup.
    # Do not remove the module until both owners report that they let go.
    try:
        command('/usr/bin/nmcli', 'device', 'set', interface, 'managed', 'no')
        for _ in range(40):
            if state(interface) == 10 and not supplicant_attached(interface):
                break
            time.sleep(0.25)
        else:
            raise RuntimeError('Supplicant did not detach; refusing an unsafe driver unload.')
        print('NetworkManager and supplicant detached; safe to reload the driver.', flush=True)
        try:
            command('/usr/bin/modprobe', '-r', 'brcmfmac_wcc', 'brcmfmac')
        finally:
            # Restore even if unloading only partially succeeded.
            command('/usr/bin/modprobe', 'brcmfmac')
    finally:
        restore_management()


def recover(force=False):
    if not supported():
        print('Unsupported hardware; leaving Wi-Fi alone.', flush=True)
        return 0
    interface = wifi()
    if not interface or not allowed(interface):
        print('Wi-Fi absent, disabled, or deliberately disconnected; skipping.', flush=True)
        return 0
    since = datetime.datetime.now().astimezone().isoformat(timespec='microseconds')
    if not force:
        first_reject_second = None
        for second in range(GRACE + 1):
            if not allowed(interface):
                print('Wi-Fi disabled/disconnected during recovery; skipping.', flush=True)
                return 0
            current = state(interface)
            if current == 100:
                print('Wi-Fi reconnected normally; no reload needed.', flush=True)
                return 0
            if 70 <= current <= 90:
                print('Wi-Fi authenticated; leaving IP configuration to NetworkManager.', flush=True)
                return 0
            count = rejects(since, interface)
            if count and first_reject_second is None:
                first_reject_second = second
            persistent_reject = count and second - first_reject_second >= REJECT_GRACE
            if count >= 2 or persistent_reject or (second == GRACE and 40 <= current <= 60):
                break
            if second == GRACE:
                print('No failed association or stuck connection; skipping reload.', flush=True)
                return 0
            time.sleep(1)
    print('Reloading brcmfmac_wcc and brcmfmac to clear failed resume state.', flush=True)
    reload_driver(interface)
    for _ in range(RECONNECT):
        interface = wifi()
        if interface:
            if not allowed(interface):
                print('Wi-Fi deliberately disabled/disconnected; stopping recovery.', flush=True)
                return 0
            if state(interface) == 100:
                print(f'Wi-Fi reconnected on {interface} after full driver reload.', flush=True)
                return 0
        time.sleep(1)
    raise RuntimeError('Driver reloaded, but Wi-Fi did not reconnect within 40 seconds.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force', action='store_true', help='Test a full reload even while connected')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run as root (use pkexec for a manual recovery).')
    try:
        return recover(args.force)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Wi-Fi recovery failed: {error}', file=sys.stderr, flush=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
