#!/usr/bin/python3
"""Install user launchers without changing or restarting Android."""
from pathlib import Path
import shutil
import subprocess

source = Path(__file__).resolve().parent
home = Path.home()
bin_dir = home / '.local/bin'
apps = home / '.local/share/applications'
bin_dir.mkdir(parents=True, exist_ok=True)
apps.mkdir(parents=True, exist_ok=True)
for name, original in [('waydroid', 'launch'), ('waydroid-shutdown', 'shutdown.py')]:
    destination = bin_dir / name
    shutil.copyfile(source / original, destination)
    destination.chmod(0o755)


def executable(name):
    path = str(bin_dir / name)
    # Desktop Entry Exec quoting, including literal percent field codes.
    for old, new in [('\\', '\\\\'), ('"', '\\"'), ('`', '\\`'), ('$', '\\$'), ('%', '%%')]:
        path = path.replace(old, new)
    return '"' + path.replace('\\', '\\\\') + '"'


(apps / 'Waydroid.desktop').write_text(f'''[Desktop Entry]
Type=Application
Name=Waydroid
Exec={executable('waydroid')} show-full-ui
Icon=waydroid
Terminal=false
Categories=Utility;
Actions=shutdown;

[Desktop Action shutdown]
Name=Shut Down Completely
Exec={executable('waydroid-shutdown')}
Icon=system-shutdown
''')
(apps / 'waydroid-shutdown.desktop').write_text(f'''[Desktop Entry]
Type=Application
Name=Shut Down Waydroid
Comment=Fully stop Android and the Waydroid container service
Exec={executable('waydroid-shutdown')}
Icon=system-shutdown
Terminal=false
Categories=Utility;
Keywords=Android;Waydroid;Stop;Shutdown;Roon;
''')
subprocess.run(['update-desktop-database', str(apps)], check=True)
print('Installed Waydroid and Shut Down Waydroid in the app launcher.')
