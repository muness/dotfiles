#!/usr/bin/python3
"""Install the user-owned Omarchy portal listener without resetting desktop config."""
import os
from pathlib import Path
import shutil
import subprocess


def main():
    if os.geteuid() == 0:
        raise SystemExit('Run as the desktop user, not root')
    home = Path.home()
    helper = home / '.local/libexec/omarchy-captive-portal'
    helper.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).with_name('captive-portal.py'), helper)
    helper.chmod(0o755)
    unit = home / '.config/systemd/user/omarchy-captive-portal.service'
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text('''[Unit]
Description=Omarchy captive Wi-Fi login assistant
PartOf=graphical-session.target
After=graphical-session.target
ConditionEnvironment=OMARCHY_PATH=/usr/share/omarchy

[Service]
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
    subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
    if os.environ.get('OMARCHY_PATH') == '/usr/share/omarchy':
        subprocess.run(['systemctl', '--user', 'restart', unit.name], check=True)
    print('Installed Omarchy captive portal listener (starts at Hyprland login).')


if __name__ == '__main__':
    main()
