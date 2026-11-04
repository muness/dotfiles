#!/usr/bin/python3
"""Install the user-owned Omarchy portal listener without resetting desktop config."""
import os
import json
from pathlib import Path
import shutil
import subprocess
import runpy


def main():
    if os.geteuid() == 0:
        raise SystemExit('Run as the desktop user, not root')
    runpy.run_path(str(Path(__file__).with_name('install-foyer.py')))['install']()
    home = Path.home()
    helper = home / '.local/libexec/omarchy-captive-portal'
    helper.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).with_name('captive-portal.py'), helper)
    helper.chmod(0o755)
    browser = helper.with_name('omarchy-portal-browser')
    shutil.copyfile(Path(__file__).with_name('portal-browser.sh'), browser)
    browser.chmod(0o755)
    unit = home / '.config/systemd/user/omarchy-captive-portal.service'
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text('''[Unit]
Description=Omarchy captive Wi-Fi login assistant
PartOf=graphical-session.target
After=graphical-session.target
ConditionEnvironment=OMARCHY_PATH=/usr/share/omarchy

[Service]
Type=dbus
BusName=org.omarchy.CaptivePortal
ExecStart=%h/.local/libexec/omarchy-captive-portal
Restart=on-failure
RestartSec=5
''')
    desktop = home / '.config/autostart/omarchy-captive-portal.desktop'
    desktop.parent.mkdir(parents=True, exist_ok=True)
    desktop.write_text('''[Desktop Entry]
Type=Application
Name=Omarchy captive Wi-Fi assistant
Exec=/usr/bin/systemctl --user start omarchy-captive-portal.service
OnlyShowIn=Hyprland;
NoDisplay=true
''')
    launcher = home / '.local/share/applications/omarchy-wifi-signin.desktop'
    launcher.parent.mkdir(parents=True, exist_ok=True)
    launcher.write_text(f'''[Desktop Entry]
Type=Application
Name=Wi-Fi Sign-in
Comment=Reopen sign-in for a Wi-Fi network requiring authentication
Exec={helper} --open
Icon=network-wireless-no-route-symbolic
Categories=Network;
OnlyShowIn=Hyprland;
''')
    activation = home / '.local/share/dbus-1/services/org.omarchy.CaptivePortal.service'
    activation.parent.mkdir(parents=True, exist_ok=True)
    activation.write_text(f'''[D-BUS Service]
Name=org.omarchy.CaptivePortal
Exec={helper}
SystemdService=omarchy-captive-portal.service
''')
    # Pinned items remain visible outside the drawer, but Passive items are
    # still hidden by Omarchy. Preserve every other layout preference.
    shell = home / '.config/omarchy/shell.json'
    if shell.exists():
        config = json.loads(shell.read_text())
        changed = False
        for section in config.get('bar', {}).get('layout', {}).values():
            for item in section:
                if isinstance(item, dict) and item.get('id') == 'omarchy.tray':
                    pinned = item.setdefault('pinned', [])
                    if 'omarchy-wifi-signin' not in pinned:
                        pinned.append('omarchy-wifi-signin')
                        changed = True
        if changed:
            backup = shell.with_name('shell.json.before-wifi-signin')
            if not backup.exists():
                shutil.copy2(shell, backup)
            shell.write_text(json.dumps(config, indent=2) + '\n')
    subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
    if os.environ.get('OMARCHY_PATH') == '/usr/share/omarchy':
        subprocess.run(['systemctl', '--user', 'restart', unit.name], check=True)
    print('Installed Omarchy captive portal listener (starts at Hyprland login).')


if __name__ == '__main__':
    main()
