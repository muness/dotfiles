#!/usr/bin/python3
"""Install the user helper and login entry after vault setup, without root."""
import json
from pathlib import Path
import shutil

home = Path.home()
config = home / '.config/session-unlock/config.json'
data = json.loads(config.read_text())
if not data.get('keyring_ref', '').startswith('op://'):
    raise SystemExit('Complete unlock.py --setup before installing autostart.')
target = home / '.local/bin/session-unlock'
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(Path(__file__).with_name('unlock.py'), target)
target.chmod(0o755)
runtime = home / '.local/lib/session-unlock'
runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
source = Path(__file__).resolve().parent
for name in ('unlock.py', 'android-unlock.py'):
    shutil.copyfile(source / name, runtime / name)
    (runtime / name).chmod(0o700)
units = home / '.config/systemd/user'
units.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source / 'session-unlock-android.service', units / 'session-unlock-android.service')
look = home / '.config/hypr/looknfeel.lua'
marker = '-- Keep the Touch ID prompt out of the tiling layout.'
if look.exists() and marker not in look.read_text():
    with look.open('a') as stream:
        stream.write('\n' + marker + '\n'
                     'o.window({ title = "^Unlock Android with Touch ID$" }, '
                     '{ float = true, center = true, size = { 440, 190 } })\n')
# Desktop Entry Exec quoting (including literal percent field codes).
quoted = str(target).replace('%', '%%')
for char in ('\\', '"', '`', '$'):
    quoted = quoted.replace(char, '\\' + char)
quoted = '"' + quoted.replace('\\', '\\\\') + '"'
entry = f'''[Desktop Entry]
Type=Application
Name=Unlock desktop keyring with 1Password
Exec={quoted} --startup
Terminal=false
'''
autostart = home / '.config/autostart/session-unlock.desktop'
autostart.parent.mkdir(parents=True, exist_ok=True)
autostart.write_text(entry)
print('Installed the keyring login helper and Android monitor unit. Root helper setup is separate.')
